import AurolightCore

extension LightMode {
    enum Group: String, CaseIterable {
        case screen = "Screen"
        case `static` = "Static"
        case ambient = "Ambient"
        case motion = "Motion"
        case music = "Music"
        case time = "Time"
    }

    struct Presentation {
        let title: String
        let symbol: String
        let group: Group
    }

    var presentation: Presentation {
        switch self {
        case .screen: Presentation(title: "Screen", symbol: "display", group: .screen)
        case .solid: Presentation(title: "Solid Color", symbol: "circle.fill", group: .static)
        case .breathing: Presentation(title: "Breathing", symbol: "wave.3.right", group: .ambient)
        case .candle: Presentation(title: "Candle", symbol: "flame", group: .ambient)
        case .aurora: Presentation(title: "Aurora", symbol: "sparkles", group: .ambient)
        case .ocean: Presentation(title: "Ocean", symbol: "water.waves", group: .ambient)
        case .lavaLamp: Presentation(title: "Lava Lamp", symbol: "drop.fill", group: .ambient)
        case .horizon: Presentation(title: "Horizon", symbol: "sunset", group: .ambient)
        case .wave: Presentation(title: "Wave", symbol: "water.waves.and.arrow.trianglehead.up", group: .motion)
        case .comet: Presentation(title: "Comet", symbol: "moon.stars", group: .motion)
        case .pulse: Presentation(title: "Pulse", symbol: "dot.radiowaves.up.forward", group: .motion)
        case .scanner: Presentation(title: "Scanner", symbol: "arrow.left.and.right", group: .motion)
        case .twinkle: Presentation(title: "Twinkle", symbol: "sparkle", group: .motion)
        case .fire: Presentation(title: "Fire", symbol: "flame.fill", group: .motion)
        case .rainbow: Presentation(title: "Rainbow", symbol: "rainbow", group: .motion)
        case .colorCycle: Presentation(title: "Color Cycle", symbol: "arrow.triangle.2.circlepath", group: .motion)
        case .music: Presentation(title: "Music", symbol: "music.note", group: .music)
        case .sunrise: Presentation(title: "Sunrise", symbol: "sunrise", group: .time)
        case .sunset: Presentation(title: "Sunset", symbol: "moon.haze", group: .time)
        }
    }

    var title: String { presentation.title }
    var symbol: String { presentation.symbol }

    static let groups: [(title: String, modes: [LightMode])] =
        Group.allCases.map { group in (group.rawValue, allCases.filter { $0.presentation.group == group }) }
}
