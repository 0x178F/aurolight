import SwiftUI

struct StatusPill: View {
    let status: AppModel.Status
    var onDismissError: () -> Void = {}
    var onOpen: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    if status == .starting || status == .stopping {
                        ProgressView().controlSize(.small)
                    } else {
                        Circle()
                            .fill(tint)
                            .frame(width: 8, height: 8)
                            .shadow(color: tint, radius: 4)
                    }
                    Text(text)
                        .font(.callout)
                        .lineLimit(2)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text)
            .accessibilityHint("Opens connection settings")
            if case .error = status {
                Button("Dismiss Error", systemImage: "xmark", action: onDismissError)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: 380, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .capsule)
        .help(tooltip)
    }

    private var tint: Color {
        switch status {
        case .connected: .green
        case .previewOnly: .yellow
        case .error: .red
        case .starting, .stopping, .stopped: .gray
        }
    }

    private var text: String {
        switch status {
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case .stopping: "Stopping…"
        case .connected: "Connected"
        case .previewOnly: "Preview only"
        case let .error(message): message
        }
    }

    private var tooltip: String {
        switch status {
        case let .connected(port):
            "Connected to \(SerialPortDiscovery.displayName(for: port)). Click for connection settings."
        case .previewOnly: "No serial port selected. Click for connection settings."
        default: "\(text). Click for connection settings."
        }
    }
}
