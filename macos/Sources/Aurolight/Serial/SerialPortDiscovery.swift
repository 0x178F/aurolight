import Foundation

enum SerialPortDiscovery {
    static func availablePorts() -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return
            entries
            .filter { $0.hasPrefix("cu.") && !$0.contains("Bluetooth") && !$0.contains("debug-console") }
            .sorted()
            .map { "/dev/" + $0 }
    }

    static func preferredPort(in ports: [String]) -> String? {
        ports.first { $0.contains("usbserial") || $0.contains("usbmodem") }
    }

    static func displayName(for path: String) -> String {
        path.replacingOccurrences(of: "/dev/cu.", with: "")
    }
}
