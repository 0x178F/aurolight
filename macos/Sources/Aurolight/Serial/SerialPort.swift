import Darwin
import Foundation

enum SerialPortError: LocalizedError {
    case open(path: String, code: Int32)
    case configure(code: Int32)
    case io(code: Int32)
    case timeout

    var errorDescription: String? {
        switch self {
        case let .open(path, code): "Failed to open port (\(path)): \(String(cString: strerror(code)))"
        case let .configure(code): "Failed to configure port: \(String(cString: strerror(code)))"
        case let .io(code): "Serial I/O error: \(String(cString: strerror(code)))"
        case .timeout: "Timed out writing to the controller"
        }
    }
}

final class SerialPort {
    let path: String
    private var fd: Int32 = -1

    private static let standardRates: Set<Int> = [9600, 19200, 38400, 57600, 115200, 230400]
    // _IOW('T', 2, speed_t): IOSSIOSPEED, sets non-standard baud rates on macOS.
    private static let iossiospeed: UInt = 0x8008_5402
    // _IOR('t', 115, int): TIOCOUTQ, bytes still waiting in the output queue.
    private static let tiocoutq: UInt = 0x4004_7473

    init(path: String) {
        self.path = path
    }

    deinit {
        close()
    }

    func open(baudRate: Int) throws {
        close()
        let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw SerialPortError.open(path: path, code: errno) }

        var t = termios()
        guard tcgetattr(fd, &t) == 0 else {
            let code = errno
            Darwin.close(fd)
            throw SerialPortError.configure(code: code)
        }
        cfmakeraw(&t)
        t.c_cflag |= tcflag_t(CLOCAL | CREAD)
        // HUPCL off: closing the port must not drop DTR, which resets many boards.
        t.c_cflag &= ~tcflag_t(CRTSCTS | HUPCL)
        let isStandard = Self.standardRates.contains(baudRate)
        cfsetspeed(&t, speed_t(isStandard ? baudRate : 115200))
        guard tcsetattr(fd, TCSANOW, &t) == 0 else {
            let code = errno
            Darwin.close(fd)
            throw SerialPortError.configure(code: code)
        }
        if !isStandard {
            var speed = speed_t(baudRate)
            guard ioctl(fd, Self.iossiospeed, &speed) == 0 else {
                let code = errno
                Darwin.close(fd)
                throw SerialPortError.configure(code: code)
            }
        }
        tcflush(fd, TCIOFLUSH)
        // Exclusive: another opener gets EBUSY instead of interleaving bytes.
        _ = ioctl(fd, TIOCEXCL)
        self.fd = fd
    }

    func close(discardPending: Bool = false) {
        guard fd >= 0 else { return }
        if !discardPending {
            let deadline = DispatchTime.now() + .milliseconds(500)
            var pending: Int32 = 0
            while ioctl(fd, Self.tiocoutq, &pending) == 0, pending > 0, DispatchTime.now() < deadline {
                usleep(2_000)
            }
        }
        tcflush(fd, TCOFLUSH)
        Darwin.close(fd)
        fd = -1
    }

    func write(_ bytes: [UInt8]) throws {
        guard fd >= 0 else { throw SerialPortError.io(code: EBADF) }
        var offset = 0
        try bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            while offset < buffer.count {
                let n = Darwin.write(fd, base + offset, buffer.count - offset)
                if n > 0 {
                    offset += n
                    continue
                }
                let code = errno
                guard n < 0, code == EAGAIN || code == EINTR else { throw SerialPortError.io(code: code) }
                var p = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                if poll(&p, 1, 500) == 0 { throw SerialPortError.timeout }
            }
        }
    }

    func readAvailable() -> [UInt8] {
        guard fd >= 0 else { return [] }
        var result: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 256)
        while true {
            let n = Darwin.read(fd, &buffer, buffer.count)
            guard n > 0 else { break }
            result += buffer[0..<n]
        }
        return result
    }
}
