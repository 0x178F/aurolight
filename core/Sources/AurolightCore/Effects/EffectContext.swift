import Foundation

struct EffectContext: Sendable {
    let settings: EffectSettings
    let layout: LEDLayout
    let time: Double
    let audio: AudioLevels

    var count: Int { layout.placedCount }
    var color: RGB { settings.color }
    var speed: Double { min(max(settings.speed, 0), 1) }
    func rate(slowest: Double, fastest: Double) -> Double {
        slowest * pow(fastest / slowest, speed)
    }
    var fadeProgress: Double { min(max(time / (max(settings.fadeMinutes, 0.1) * 60), 0), 1) }
}
