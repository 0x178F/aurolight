import AppKit
import SwiftUI

struct PermissionStep: View {
    private static let screenRecordingSettings =
        URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        ?? URL(fileURLWithPath: "/System/Applications/System Settings.app")

    @State private var granted = CGPreflightScreenCaptureAccess()
    @State private var requested = false
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingStepHeader(
                symbol: "rectangle.dashed.badge.record",
                title: "Let Aurolight see your screen",
                message: """
                    Screen sync reads the colors at the edges of your display and the Music mode listens to what \
                    your Mac plays. Nothing is recorded, stored or sent anywhere.
                    """
            )

            if granted {
                Label("Screen Recording is allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                HStack(spacing: 12) {
                    Button("Allow Screen Recording") {
                        CGRequestScreenCaptureAccess()
                        requested = true
                    }
                    .buttonStyle(.glassProminent)
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(Self.screenRecordingSettings)
                        requested = true
                    }
                    .buttonStyle(.glass)
                }
                if requested {
                    HStack(spacing: 10) {
                        Text("Turned it on? macOS applies it after a relaunch.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Relaunch") { relaunch() }
                            .buttonStyle(.link)
                    }
                }
            }
        }
        .onReceive(poll) { _ in granted = CGPreflightScreenCaptureAccess() }
    }

    private func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
