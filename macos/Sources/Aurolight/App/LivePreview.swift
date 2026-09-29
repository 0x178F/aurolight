import AurolightCore
import CoreGraphics
import Observation

@MainActor
@Observable
final class LivePreview {
    var colors: [RGB] = []
    var screenImage: CGImage?
}
