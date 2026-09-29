import AurolightCore
import SwiftUI

struct CountControl: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...LEDLayout.maxPerEdge
    var axis: Axis = .horizontal

    @State private var isEditing = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let stack =
            axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 2))
            : AnyLayout(VStackLayout(spacing: 2))

        stack {
            if axis == .horizontal {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                    .padding(.trailing, 2)
                stepButton(-1, symbol: "minus")
                field
                stepButton(1, symbol: "plus")
            } else {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                stepButton(1, symbol: "plus")
                field
                stepButton(-1, symbol: "minus")
            }
        }
        .padding(4)
        .help("\(title): \(value)")
        .accessibilityElement(children: isEditing ? .contain : .ignore)
        .accessibilityLabel("\(title) LEDs")
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: clamped.wrappedValue = value + 1
            case .decrement: clamped.wrappedValue = value - 1
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Type value") { isEditing = true }
    }

    @ViewBuilder
    private var field: some View {
        Group {
            if isEditing {
                TextField(title, value: clamped, format: .number)
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .focused($fieldFocused)
                    .onSubmit { isEditing = false }
                    .onChange(of: fieldFocused) { _, focused in
                        if !focused { isEditing = false }
                    }
                    .onAppear { fieldFocused = true }
            } else {
                Text(value, format: .number)
                    .contentShape(.rect)
                    .onTapGesture { isEditing = true }
                    .help("Click to type a value")
            }
        }
        .multilineTextAlignment(.center)
        .font(.body.monospacedDigit().weight(.semibold))
        .frame(width: 38)
    }

    private func stepButton(_ delta: Int, symbol: String) -> some View {
        Button {
            clamped.wrappedValue = value + delta
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .disabled(delta < 0 ? value <= range.lowerBound : value >= range.upperBound)
    }

    private var clamped: Binding<Int> {
        Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }
}
