import AurolightCore
import Foundation

final class SerialAdalightOutput: LightOutput {
    private let port: SerialPort
    private var pacer: AdalightFramePacer

    init(path: String, baudRate: Int) throws {
        port = SerialPort(path: path)
        do {
            try port.open(baudRate: baudRate)
        } catch {
            Log.serial.error("Open failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        pacer = AdalightFramePacer(baudRate: baudRate, openedAt: Self.now())
    }

    func submit(_ rgb: [UInt8]) throws {
        if !port.readAvailable().isEmpty { pacer.acknowledge() }
        let now = Self.now()
        guard pacer.shouldSend(rgb, at: now) else { return }
        do {
            try port.write(Adalight.frame(rgb: rgb))
            pacer.didSend(rgb, at: now)
        } catch {
            Log.serial.error("Write failed: \(error.localizedDescription, privacy: .public)")
            port.close(discardPending: true)
            throw error
        }
    }

    func keepAlive(ledCount: Int) throws {
        let last = pacer.lastFrame
        guard !last.isEmpty, last.count == ledCount * 3 else { return }
        try submit(last)
    }

    func close(ledCount: Int) {
        let deadline = Self.now() + 0.3
        while !pacer.isReady(at: Self.now()), Self.now() < deadline {
            if !port.readAvailable().isEmpty { pacer.acknowledge() }
            usleep(2_000)
        }
        do {
            try port.write(Adalight.frame(rgb: [UInt8](repeating: 0, count: max(ledCount, 1) * 3)))
            port.close()
        } catch {
            port.close(discardPending: true)
        }
    }

    private static func now() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1e9
    }
}
