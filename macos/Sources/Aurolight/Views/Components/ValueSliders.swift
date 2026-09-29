import SwiftUI

struct PercentControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledSlider(
            title: title, value: $value, range: range, text: value.formatted(.percent.precision(.fractionLength(0))))
    }
}

struct DecimalControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        LabeledSlider(
            title: title, value: $value, range: range, text: value.formatted(.number.precision(.fractionLength(1))))
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let text: String

    var body: some View {
        PanelControl(title: title, value: text) {
            Slider(value: $value, in: range) { Text(title) }
                .labelsHidden()
                .accessibilityValue(text)
        }
    }
}
