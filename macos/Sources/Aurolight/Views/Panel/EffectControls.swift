import AurolightCore
import SwiftUI

struct EffectControls: View {
    @Binding var effects: EffectSettings
    @Binding var color: ColorSettings

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            if effects.mode.controls.contains(.color) {
                PanelControl(title: "Color", value: hex(effects.color)) {
                    ColorBar(color: $effects.color)
                }
                .fixedSize(horizontal: true, vertical: false)
                ColumnDivider()
            }
            if effects.mode.controls.contains(.speed) {
                PercentControl(title: "Speed", value: $effects.speed, range: 0...1)
                ColumnDivider()
            }
            if effects.mode.controls.contains(.duration) {
                LabeledSlider(
                    title: "Duration", value: minutesBinding, range: 1...60, text: "\(Int(effects.fadeMinutes)) min")
                ColumnDivider()
            }
            if effects.mode == .music {
                PanelControl(title: "Music") {
                    Text("Sound enters at the bottom and rises up both sides: bass amber, mids teal, treble violet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .help("Reacts to audio playing on this Mac and adapts to its volume.")
                ColumnDivider()
            }
            PercentControl(title: "Brightness", value: $color.brightness, range: 0.05...1)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var minutesBinding: Binding<Double> {
        Binding(get: { effects.fadeMinutes }, set: { effects.fadeMinutes = $0.rounded() })
    }

    private func hex(_ rgb: RGB) -> String {
        "#" + [rgb.r, rgb.g, rgb.b].map { String(format: "%02X", ColorProcessor.byte($0)) }.joined()
    }
}
