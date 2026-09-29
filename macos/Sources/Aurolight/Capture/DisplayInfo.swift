import AppKit

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let aspectRatio: Double

    @MainActor
    static func all() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let size = screen.frame.size
            return DisplayInfo(
                id: number.uint32Value,
                name: screen.localizedName,
                aspectRatio: size.height > 0 ? size.width / size.height : 16 / 9
            )
        }
    }
}
