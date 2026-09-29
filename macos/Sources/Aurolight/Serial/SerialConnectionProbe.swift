import AurolightCore
import Foundation

enum SerialConnectionProbe {
    enum Result: Equatable {
        case responded, noResponse
        case failed(String)
    }

    static func run(path: String, baudRate: Int) async -> Result {
        let port = SerialPort(path: path)
        do {
            try port.open(baudRate: baudRate)
        } catch {
            return .failed(error.localizedDescription)
        }
        defer { port.close(discardPending: true) }
        let probeFrame = Adalight.frame(rgb: [0, 0, 0])
        var received: [UInt8] = []
        var acksFrom: Int?
        for tick in 0..<60 {
            received += port.readAvailable()
            if received.contains(Adalight.magic) { return .responded }
            if let acksFrom, received[acksFrom...].contains(UInt8(ascii: "K")) { return .responded }
            if tick >= 25, tick.isMultiple(of: 5) {
                acksFrom = acksFrom ?? received.count
                try? port.write(probeFrame)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return .noResponse
    }
}
