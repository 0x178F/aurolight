import AppKit
import AurolightCore
import SwiftUI

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case video, permission, controller, layout, white
    }

    static let stepKey = "onboardingStep"
    private static let introURL = Bundle.main.url(forResource: "Intro", withExtension: "mp4")

    @Bindable var model: AppModel
    @AppStorage(OnboardingView.stepKey) private var stepValue = Step.video.rawValue

    private var step: Step {
        let stored = Step(rawValue: stepValue) ?? .video
        return stored == .video && Self.introURL == nil ? .permission : stored
    }

    var body: some View {
        ZStack {
            if step == .video, let url = Self.introURL {
                videoStep(url)
                    .transition(.opacity)
            } else if step == .white {
                WhiteCalibration(model: model) {
                    Button("Back") { go(to: .layout) }
                        .buttonStyle(.glass)
                    Button("Finish Setup") { finish() }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .transition(.opacity)
            } else {
                setupCard
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.smooth(duration: 0.4), value: stepValue)
    }

    private func videoStep(_ url: URL) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            IntroVideoView(url: url) { go(to: .permission) }
                .ignoresSafeArea()
            Button("Skip") { go(to: .permission) }
                .buttonStyle(.glass)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                .padding(24)
        }
    }

    private var setupCard: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                Group {
                    switch step {
                    case .video, .permission: PermissionStep()
                    case .controller: ControllerStep(model: model)
                    case .layout: LayoutStep(layout: $model.settings.layout)
                    case .white: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                footer
            }
            .padding(36)
            .frame(width: 600)
            .background(.regularMaterial, in: .rect(cornerRadius: 30))
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 8) {
                ForEach(steps, id: \.self) { s in
                    Capsule()
                        .fill(s == step ? Color.primary : Color.secondary.opacity(0.35))
                        .frame(width: s == step ? 22 : 8, height: 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \((steps.firstIndex(of: step) ?? 0) + 1) of \(steps.count)")
            Spacer()
            if step != .permission {
                Button("Back") { go(to: Step(rawValue: step.rawValue - 1) ?? .permission) }
                    .buttonStyle(.glass)
            }
            if step == steps.last {
                Button("Start Aurolight") { finish() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { go(to: Step(rawValue: step.rawValue + 1) ?? .layout) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
    }

    // The white can only be matched on a strip; preview only skips it.
    private var steps: [Step] {
        model.settings.portPath == nil
            ? [.permission, .controller, .layout] : [.permission, .controller, .layout, .white]
    }

    private func go(to step: Step) {
        stepValue = step.rawValue
    }

    private func finish() {
        UserDefaults.standard.removeObject(forKey: Self.stepKey)
        model.completeOnboarding()
        if !model.isRunning, CGPreflightScreenCaptureAccess() { model.start() }
    }
}
