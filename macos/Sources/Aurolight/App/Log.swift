import os

enum Log {
    private static let subsystem = "com.fatihakdogan.aurolight"
    static let serial = Logger(subsystem: subsystem, category: "serial")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let settings = Logger(subsystem: subsystem, category: "settings")
}
