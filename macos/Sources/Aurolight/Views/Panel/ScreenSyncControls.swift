import AurolightCore
import SwiftUI

struct ScreenSyncControls: View {
    @Binding var color: ColorSettings

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                presetControl
                    .frame(width: Self.firstColumn)
                ColumnDivider()
                PercentControl(title: "Brightness", value: $color.brightness, range: 0.05...1)
                ColumnDivider()
                PercentControl(title: "Immersion", value: $color.immersion, range: 0...1)
                    .help(
                        """
                        How much the rest of the screen, not just its edges, lights the strip. When an edge is dark, \
                        colorful things further in, like an explosion, light the side they're on.
                        """)
            }

            if color.preset == .custom {
                RowDivider()
                HStack(alignment: .top, spacing: 20) {
                    HStack(alignment: .top, spacing: 20) {
                        PercentControl(title: "Smoothing", value: $color.smoothing, range: 0...0.95)
                            .help("Slower transitions look calmer; faster ones follow quick cuts.")
                        DecimalControl(title: "Saturation", value: $color.saturation, range: 0...2)
                            .help("1.0 keeps the colors of the screen.")
                    }
                    .frame(width: Self.firstColumn)
                    ColumnDivider()
                    DecimalControl(title: "Gamma", value: $color.gamma, range: 1...3)
                        .help("2.2 matches the screen. Lower lifts dark scenes and pales colors; higher deepens them.")
                    ColumnDivider()
                    PercentControl(title: "Dark cutoff", value: $color.blackLevel, range: 0...0.2)
                        .help("Colors darker than this turn the LEDs off, so dark scenes don't flicker.")
                }
                .transition(.opacity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private static let firstColumn: CGFloat = 290

    private var presetControl: some View {
        PanelControl(title: "Preset") {
            Picker("Preset", selection: presetBinding) {
                ForEach(ColorPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        } accessory: {
            Button("Reset Tuning", systemImage: "arrow.counterclockwise") {
                withAnimation(.smooth) { color = defaultTuning }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Back to the Natural preset and its tuning. Brightness and immersion stay as they are.")
            .disabled(color == defaultTuning)
        }
    }

    private var defaultTuning: ColorSettings {
        ColorSettings(brightness: color.brightness, immersion: color.immersion)
    }

    private var presetBinding: Binding<ColorPreset> {
        Binding(
            get: { color.preset },
            set: { preset in withAnimation(.smooth) { color.select(preset) } }
        )
    }
}
