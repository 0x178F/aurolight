import AurolightCore
import Combine
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @State private var screenRect: CGRect?
    @State private var showsConnection = false

    var body: some View {
        @Bindable var model = model

        ZStack {
            LiveBiasLightGlow(layout: model.settings.layout, live: model.live, screen: screenRect)

            VStack(spacing: 16) {
                LayoutEditor(
                    layout: $model.settings.layout,
                    live: model.live,
                    aspectRatio: model.selectedDisplay?.aspectRatio ?? 16 / 9,
                    showsScreen: model.settings.effects.mode == .screen,
                    skippedArea: model.settings.effects.mode == .screen ? model.detectedArea : .uniform(0)
                )
                SettingsPanel(model: model)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .padding(.top, 8)
        }
        .coordinateSpace(.named(ScreenRectKey.coordinateSpace))
        .onPreferenceChange(ScreenRectKey.self) { screenRect = $0 }
        .toolbar { toolbarContent }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(
            model.settings.onboardingCompleted && !model.isCalibratingWhite ? .visible : .hidden, for: .windowToolbar
        )
        .overlay {
            if !model.settings.onboardingCompleted {
                OnboardingView(model: model)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.5), value: model.settings.onboardingCompleted)
        .overlay {
            if model.isCalibratingWhite {
                WhiteCalibration(model: model) {
                    Button("Cancel") { model.endWhiteCalibration(keep: false) }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                    Button("Done") { model.endWhiteCalibration(keep: true) }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: model.isCalibratingWhite)
        .containerBackground(for: .window) { WindowGlass() }
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshSnapshot()
        }
        .onReceive(Self.visibilityEvents) { _ in model.updateWindowVisibility() }
        .onAppear { DispatchQueue.main.async { model.updateWindowVisibility() } }
        .onDisappear { DispatchQueue.main.async { model.updateWindowVisibility() } }
    }

    private static let visibilityEvents = Publishers.MergeMany(
        [
            NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification, NSWindow.didBecomeKeyNotification,
            NSApplication.didHideNotification, NSApplication.didUnhideNotification,
            NSApplication.didBecomeActiveNotification,
        ].map { NotificationCenter.default.publisher(for: $0) })

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Text("Aurolight")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 6)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .principal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    StatusPill(
                        status: model.status,
                        onDismissError: model.dismissError
                    ) {
                        showsConnection.toggle()
                    }
                    .popover(isPresented: $showsConnection, arrowEdge: .bottom) {
                        ConnectionMenu(model: model)
                    }
                    startButton
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.flexible)

        ToolbarItem(placement: .automatic) {
            modeMenu
        }
    }

    private var modeMenu: some View {
        @Bindable var model = model
        let mode = model.settings.effects.mode
        return Menu {
            LightModePicker(selection: $model.settings.effects.mode)
        } label: {
            Label(mode.title, systemImage: mode.symbol)
                .labelStyle(.titleAndIcon)
        }
        .fixedSize()
        .help("Light mode: follow the screen or run an effect")
    }

    private var startButton: some View {
        Button {
            model.toggle()
        } label: {
            Label(
                model.isRunning ? "Stop" : "Start",
                systemImage: model.isRunning ? "stop.fill" : "play.fill"
            )
            .labelStyle(.iconOnly)
            .font(.callout.weight(.semibold))
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .tint(model.isRunning ? .red : nil)
        .help(model.isRunning ? "Stop (⌘R)" : "Start (⌘R)")
        .disabled(model.isBusy)
        .keyboardShortcut("r", modifiers: .command)
    }
}
