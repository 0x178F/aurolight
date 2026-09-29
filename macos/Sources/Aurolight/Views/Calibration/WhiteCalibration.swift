import AurolightCore
import SwiftUI

struct WhiteCalibration<Actions: View>: View {
    @Bindable var model: AppModel
    @ViewBuilder var actions: Actions

    @State private var calibration = WhiteBalanceCalibration()
    @State private var shown = 0
    @State private var hovered: Int?
    @State private var showsFineTuning = false

    private var current: Int { hovered ?? shown }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Calibrate the white")
                        .font(.title2.weight(.semibold))
                    Text(prompt)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.isBusy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Turning the strip on…").foregroundStyle(.secondary)
                    }
                } else if !model.isRunning {
                    HStack(spacing: 10) {
                        Label(model.errorMessage ?? "The strip is off.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Try Again") { model.start() }
                            .buttonStyle(.glass)
                    }
                } else if calibration.phase == .done {
                    Label("Calibrated", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    comparison
                }

                DisclosureGroup("Fine-tune", isExpanded: $showsFineTuning) { fineTuning }
                    .font(.callout)

                HStack(spacing: 10) {
                    Spacer()
                    actions
                }
                .controlSize(.large)
            }
            .padding(28)
            .frame(width: 560)
            .background(.regularMaterial, in: .rect(cornerRadius: 26))
            .padding(.bottom, 40)
        }
        .onAppear {
            preview()
            if !model.isRunning { model.start() }
        }
        .onDisappear { model.calibrationPreview = nil }
        .onChange(of: current) { preview() }
        .onChange(of: showsFineTuning) {
            if showsFineTuning { calibration.finish() }
            preview()
        }
        .onChange(of: model.settings.whiteBalance) { if calibration.phase == .done { preview() } }
        .task(id: calibration.answered) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                if hovered == nil { shown = 1 - shown }
            }
        }
    }

    private var prompt: String {
        switch calibration.phase {
        case .warmth, .tint:
            "The strip switches between 1 and 2. Pick the one whose light on the wall looks more like this white."
        case .done:
            "The strip now shows your white. Fine-tune it if something still looks off."
        }
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { option in
                    Button {
                        choose(option)
                    } label: {
                        Text("\(option + 1)")
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .frame(width: 72, height: 44)
                    }
                    .buttonStyle(.glass)
                    .tint(current == option ? .accentColor : nil)
                    .onHover { inside in
                        if inside { hovered = option } else if hovered == option { hovered = nil }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(option + 1)")), modifiers: [])
                    .accessibilityLabel("White \(option + 1)")
                    .accessibilityAddTraits(current == option ? .isSelected : [])
                }
                Button("They Look the Same") { chooseNeither() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .padding(.leading, 6)
            }
            HStack(spacing: 6) {
                ForEach(0..<WhiteBalanceCalibration.rounds, id: \.self) { round in
                    Capsule()
                        .fill(round < calibration.answered ? Color.primary : Color.secondary.opacity(0.35))
                        .frame(width: round == calibration.answered ? 18 : 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Comparison \(calibration.answered + 1) of \(WhiteBalanceCalibration.rounds)")
        }
    }

    private var fineTuning: some View {
        VStack(spacing: 12) {
            Slider(value: $model.settings.whiteBalance.temperature, in: WhiteBalance.temperatureRange) {
                Text("Warmth")
            } minimumValueLabel: {
                Text("Warm")
            } maximumValueLabel: {
                Text("Cool")
            }
            Slider(value: $model.settings.whiteBalance.tint, in: -1...1) {
                Text("Tint")
            } minimumValueLabel: {
                Text("Green")
            } maximumValueLabel: {
                Text("Magenta")
            }
            HStack {
                Spacer()
                Button("Start Over", action: startOver)
            }
        }
        .padding(.top, 8)
    }

    private func preview() {
        model.calibrationPreview =
            calibration.phase == .done ? model.settings.whiteBalance : calibration.candidate(current)
    }

    private func choose(_ option: Int) {
        calibration.choose(option)
        advanced()
    }

    private func chooseNeither() {
        calibration.chooseNeither()
        advanced()
    }

    private func advanced() {
        shown = 0
        hovered = nil
        model.settings.whiteBalance = calibration.result
        preview()
    }

    private func startOver() {
        calibration = WhiteBalanceCalibration()
        showsFineTuning = false
        model.settings.whiteBalance = .neutral
        preview()
    }
}
