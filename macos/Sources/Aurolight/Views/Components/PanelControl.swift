import SwiftUI

struct PanelControl<Content: View, Accessory: View>: View {
    let title: String
    var value: String?
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
                if let value {
                    Text(value)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                accessory
            }
            .frame(height: 20)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension PanelControl where Accessory == EmptyView {
    init(title: String, value: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, value: value, content: content, accessory: { EmptyView() })
    }
}

struct ColumnDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
            .frame(width: 1)
            .padding(.vertical, 2)
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
            .frame(height: 1)
    }
}
