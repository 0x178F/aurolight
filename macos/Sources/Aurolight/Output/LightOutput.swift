protocol LightOutput: AnyObject {
    func submit(_ rgb: [UInt8]) throws
    func keepAlive(ledCount: Int) throws
    func close(ledCount: Int)
}

enum OutputConfiguration: Equatable, Sendable {
    case preview
    case serial(path: String, baudRate: Int)

    func open() throws -> LightOutput? {
        switch self {
        case .preview: nil
        case let .serial(path, baudRate): try SerialAdalightOutput(path: path, baudRate: baudRate)
        }
    }
}
