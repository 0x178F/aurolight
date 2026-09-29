import AurolightCore
import SwiftUI

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model

        Button(model.isRunning ? "Stop" : "Start") { model.toggle() }
            .disabled(model.isBusy)
        Divider()
        LightModePicker(selection: $model.settings.effects.mode)
        Divider()
        Button("Open Aurolight") {
            AppDelegate.showMainWindow { openWindow(id: "main") }
        }
        .keyboardShortcut("o")
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
