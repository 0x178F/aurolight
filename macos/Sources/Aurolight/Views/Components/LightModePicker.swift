import AurolightCore
import SwiftUI

struct LightModePicker: View {
    @Binding var selection: LightMode

    var body: some View {
        ForEach(LightMode.groups, id: \.title) { group in
            Picker(group.title, selection: $selection) {
                ForEach(group.modes) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.inline)
        }
    }
}
