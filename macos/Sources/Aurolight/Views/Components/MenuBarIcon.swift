import AppKit

enum MenuBarIcon {
    static func image(running: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: true) { _ in
            NSColor.black.set()
            let screen = NSBezierPath(
                roundedRect: NSRect(x: 4, y: 3.5, width: 12, height: 8), xRadius: 1.6, yRadius: 1.6)
            screen.lineWidth = 1.4
            screen.stroke()
            NSRect(x: 9.3, y: 11.5, width: 1.4, height: 2).fill()
            NSBezierPath(roundedRect: NSRect(x: 7, y: 13.3, width: 6, height: 1.4), xRadius: 0.7, yRadius: 0.7).fill()

            NSColor.black.withAlphaComponent(running ? 1 : 0.35).set()
            func dot(_ x: CGFloat, _ y: CGFloat) {
                NSBezierPath(ovalIn: NSRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)).fill()
            }
            for x in [5.5, 8.5, 11.5, 14.5] { dot(x, 1.2) }
            for y in [5.5, 8.5] {
                dot(1.4, y)
                dot(18.6, y)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = running ? "Aurolight (running)" : "Aurolight (stopped)"
        return image
    }
}
