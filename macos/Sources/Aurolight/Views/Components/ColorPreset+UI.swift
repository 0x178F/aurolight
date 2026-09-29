import AurolightCore

extension ColorPreset {
    var title: String {
        switch self {
        case .natural: "Natural"
        case .vivid: "Vivid"
        case .cinema: "Cinema"
        case .custom: "Custom"
        }
    }
}
