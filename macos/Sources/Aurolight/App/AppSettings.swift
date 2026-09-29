import AurolightCore

struct AppSettings: Codable, Equatable {
    var layout = LEDLayout()
    var color = ColorSettings()
    var effects = EffectSettings()
    var whiteBalance = WhiteBalance.neutral
    var portPath: String?
    // Must match BAUD_RATE in firmware/Aurolight/Board.h.
    var baudRate = 115200
    static let baudRates = [115200, 230400, 500000, 921600, 2_000_000]
    static let baudRateHint =
        "Match the firmware: 115200 for Arduino, 921600 for ESP32 and ESP8266. Native-USB boards ignore it."
    var output: OutputConfiguration {
        portPath.map { .serial(path: $0, baudRate: baudRate) } ?? .preview
    }
    var displayID: UInt32?
    var onboardingCompleted = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        layout = c.decode(.layout, default: d.layout)
        color = c.decode(.color, default: d.color)
        effects = c.decode(.effects, default: d.effects)
        whiteBalance = c.decode(.whiteBalance, default: d.whiteBalance)
        portPath = c.decodeLenient(.portPath)
        baudRate = c.decode(.baudRate, default: d.baudRate)
        displayID = c.decodeLenient(.displayID)
        onboardingCompleted = c.decode(.onboardingCompleted, default: d.onboardingCompleted)
    }
}
