import SwiftUI

struct ControllerStep: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingStepHeader(
                symbol: "cable.connector",
                title: "Connect your LED controller",
                message: "Plug the controller that drives your strip into a USB port, then pick it below.")

            HStack(spacing: 10) {
                Picker("Serial port", selection: $model.settings.portPath) {
                    Text("None (preview only)").tag(String?.none)
                    ForEach(model.ports, id: \.self) { port in
                        Text(SerialPortDiscovery.displayName(for: port)).tag(Optional(port))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 280)
                Button("Refresh", systemImage: "arrow.clockwise") { model.refreshDevices() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                Button("Test Connection") { model.testConnection() }
                    .buttonStyle(.glass)
                    .disabled(model.settings.portPath == nil || model.connectionTest == .testing || model.isBusy)
            }

            VStack(alignment: .leading, spacing: 6) {
                Picker("Baud rate", selection: $model.settings.baudRate) {
                    ForEach(AppSettings.baudRates, id: \.self) { Text(String($0)).tag($0) }
                }
                .frame(maxWidth: 280)
                .disabled(model.isBusy)
                Text(AppSettings.baudRateHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            result
        }
        .onAppear {
            model.refreshDevices()
            model.resetConnectionTest()
        }
    }

    @ViewBuilder
    private var result: some View {
        switch model.connectionTest {
        case .idle:
            Text("Testing is optional: the controller should answer within a few seconds.")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .testing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for the controller…").font(.callout)
            }
        case .responded:
            Label("Controller responded. You're connected.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.headline)
        case .noResponse:
            Label(
                "No response. Check the cable and that the controller runs the Aurolight firmware.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
            .font(.callout)
        case let .failed(message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .font(.callout)
        }
    }
}
