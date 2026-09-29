import Foundation

func pseudoRandom(_ i: Int, _ j: Int) -> Double {
    fract(sin(Double(i) * 127.1 + Double(j) * 311.7 + 74.7) * 43758.5453)
}

func valueNoise(_ x: Double, _ y: Double) -> Double {
    let xi = Int(x.rounded(.down)), yi = Int(y.rounded(.down))
    let fx = x - Double(xi), fy = y - Double(yi)
    let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
    let top = pseudoRandom(xi, yi) + (pseudoRandom(xi + 1, yi) - pseudoRandom(xi, yi)) * sx
    let bottom = pseudoRandom(xi, yi + 1) + (pseudoRandom(xi + 1, yi + 1) - pseudoRandom(xi, yi + 1)) * sx
    return top + (bottom - top) * sy
}

func screenPoint(_ slot: LEDSlot) -> (x: Double, y: Double) {
    switch slot.edge {
    case .top: (slot.position, 0)
    case .bottom: (slot.position, 1)
    case .left: (0, slot.position)
    case .right: (1, slot.position)
    }
}

func fract(_ v: Double) -> Double { v - v.rounded(.down) }

func circularDistance(_ a: Double, _ b: Double) -> Double {
    let d = abs(a - b)
    return min(d, 1 - d)
}
