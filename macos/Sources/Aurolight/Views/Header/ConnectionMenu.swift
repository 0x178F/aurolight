import SwiftUI

struct ConnectionMenu: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                LabeledContent("Serial port") {
                    HStack(spacing: 6) {
                        Picker("Serial port", selection: $model.settings.portPath) {
                            Text("None (preview only)").tag(String?.none)
                            ForEach(model.ports, id: \.self) { port in
                                Text(SerialPortDiscovery.displayName(for: port)).tag(Optional(port))
                            }
                        }
                        .labelsHidden()
                        .disabled(model.isBusy)
                        Button("Refresh", systemImage: "arrow.clockwise") { model.refreshDevices() }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Rescan serial ports and displays")
                    }
                }
                Picker("Baud rate", selection: $model.settings.baudRate) {
                    ForEach(AppSettings.baudRates, id: \.self) { Text(String($0)).tag($0) }
                }
                .disabled(model.isBusy)
            } footer: {
                Text(AppSettings.baudRateHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Calibrate White…") {
                    dismiss()
                    model.calibrateWhite()
                }
                .disabled(model.settings.portPath == nil)
            } footer: {
                Text("Makes the strip's white look like your screen's.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.displays.count > 1 {
                Section {
                    Picker("Display", selection: $model.settings.displayID) {
                        Text("Main display").tag(UInt32?.none)
                        ForEach(model.displays) { display in
                            Text(display.name).tag(Optional(display.id))
                        }
                    }
                    .disabled(model.isBusy)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.refreshDevices() }
    }
}
