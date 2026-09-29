import SwiftUI

struct SettingsPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.settings.effects.mode == .screen {
                ScreenSyncControls(color: $model.settings.color)
            } else {
                EffectControls(effects: $model.settings.effects, color: $model.settings.color)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: ConcentricRectangle(corners: .concentric(minimum: 20), isUniform: true))
    }
}
