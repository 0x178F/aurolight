import AppKit
import AurolightCore
import Observation

@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case stopped
        case starting
        case stopping
        case connected(port: String)
        case previewOnly
        case error(String)
    }

    var settings: AppSettings {
        didSet { settingsChanged(from: oldValue) }
    }
    private(set) var ports: [String] = []
    private(set) var displays: [DisplayInfo] = []
    private(set) var isRunning = false
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var activeOutput: OutputConfiguration?
    let live = LivePreview()
    private(set) var detectedArea = EdgeValues.uniform(0)
    var isCalibratingWhite = false
    /// While calibrating, the strip shows full white in this balance instead of the mode; never saved.
    var calibrationPreview: WhiteBalance? {
        didSet { engine.update(engineConfig) }
    }
    @ObservationIgnored private var balanceBeforeCalibration = WhiteBalance.neutral

    @ObservationIgnored private let store = SettingsStore()
    @ObservationIgnored private let engine: LightEngine
    @ObservationIgnored private var launchTask: Task<Void, Error>?
    @ObservationIgnored private var launchFaulted = false
    @ObservationIgnored private var filteredWindows: Set<Int> = []
    @ObservationIgnored private var resumePending = false
    @ObservationIgnored private var resumeTask: Task<Void, Never>?
    @ObservationIgnored private var isAsleep = false
    @ObservationIgnored private var systemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var snapshotTask: Task<Void, Never>?
    private static let resumeInterval = Duration.seconds(2)

    private static let screenRecordingHint = """
        Screen Recording permission required. Grant it in System Settings › Privacy & Security › \
        Screen & System Audio Recording, then relaunch.
        """

    init() {
        let settings = store.load()
        self.settings = settings
        engine = LightEngine(config: Self.engineConfig(settings))
        engine.setHandlers(
            .init(
                preview: { [weak self] colors in self?.live.colors = colors },
                fault: { [weak self] error in self?.handleEngineFault(error) },
                thumbnail: { [weak self] image in self?.live.screenImage = image },
                detectedArea: { [weak self] area in self?.detectedArea = area }))
        refreshDevices()
        refreshSnapshot()
        observeSystem()
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor () -> Void)
        {
            systemObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated { action() }
                })
        }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in self?.systemWillSleep() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in self?.systemWillSleep() }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in self?.systemDidWake() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in self?.systemDidWake() }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.displaysChanged()
        }
    }

    private func systemWillSleep() {
        isAsleep = true
        guard isRunning, !isBusy else { return }
        resumePending = true
        isBusy = true
        Task {
            await stopEngine()
            isBusy = false
        }
    }

    private func systemDidWake() {
        isAsleep = false
        if resumePending { scheduleResume() }
    }

    private func displaysChanged() {
        displays = DisplayInfo.all()
        if isRunning { engine.displayConfigurationChanged(displayID: activeDisplayID) } else { refreshSnapshot() }
    }

    private func scheduleResume() {
        resumeTask?.cancel()
        resumeTask = Task {
            while !Task.isCancelled, resumePending {
                try? await Task.sleep(for: Self.resumeInterval)
                guard !Task.isCancelled, resumePending, !isAsleep, !isBusy, !isRunning else { continue }
                if LightEngine.captureProfile(for: engineConfig) != nil, !CGPreflightScreenCaptureAccess() {
                    cancelResume()
                    return
                }
                ports = SerialPortDiscovery.availablePorts()
                if case let .serial(path, _) = settings.output, !ports.contains(path) { continue }
                beginStart()
            }
        }
    }

    private func cancelResume() {
        resumePending = false
        resumeTask?.cancel()
        resumeTask = nil
    }

    func refreshSnapshot() {
        guard !isRunning, CGPreflightScreenCaptureAccess() else { return }
        let displayID = activeDisplayID
        snapshotTask?.cancel()
        snapshotTask = Task {
            let image = try? await ScreenCapture.snapshot(displayID: displayID, width: 960)
            guard let image, !Task.isCancelled, !isRunning, displayID == activeDisplayID else { return }
            live.screenImage = image
        }
    }

    var status: Status {
        if let errorMessage { return .error(errorMessage) }
        if isBusy { return isRunning ? .stopping : connectionTest == .testing ? .stopped : .starting }
        guard isRunning else { return .stopped }
        if case let .serial(path, _)? = activeOutput { return .connected(port: path) }
        return .previewOnly
    }

    var selectedDisplay: DisplayInfo? {
        displays.first { $0.id == settings.displayID } ?? displays.first { $0.id == CGMainDisplayID() }
    }

    private var activeDisplayID: CGDirectDisplayID {
        selectedDisplay?.id ?? settings.displayID ?? CGMainDisplayID()
    }

    func refreshDevices() {
        ports = SerialPortDiscovery.availablePorts()
        displays = DisplayInfo.all()
        if !settings.onboardingCompleted, settings.portPath == nil,
            let usb = SerialPortDiscovery.preferredPort(in: ports)
        {
            settings.portPath = usb
        }
    }

    enum ConnectionTest: Equatable {
        case idle, testing, responded, noResponse
        case failed(String)
    }

    private(set) var connectionTest = ConnectionTest.idle

    func resetConnectionTest() {
        connectionTest = .idle
    }

    func completeOnboarding() {
        settings.onboardingCompleted = true
    }

    func testConnection() {
        guard case let .serial(path, baudRate) = settings.output, !isBusy else { return }
        let tested = settings.output
        connectionTest = .testing
        let wasRunning = isRunning
        isBusy = true
        Task {
            if wasRunning {
                await stopEngine()
                errorMessage = nil
            }
            let result = await Task.detached { await SerialConnectionProbe.run(path: path, baudRate: baudRate) }.value
            isBusy = false
            guard settings.output == tested else { return }
            connectionTest =
                switch result {
                case .responded: .responded
                case .noResponse: .noResponse
                case let .failed(message): .failed(message)
                }
        }
    }

    func toggle() {
        if isRunning { stop() } else { start() }
    }

    func updateWindowVisibility() {
        let windows = NSApp.windows.filter(AppDelegate.isMainWindow)
        let hidden =
            NSApp.isHidden
            || (!windows.isEmpty
                && windows.allSatisfy { !$0.isVisible || $0.isMiniaturized || !$0.occlusionState.contains(.visible) })
        engine.setPreviewVisible(!hidden)
        let numbers = Set(NSApp.windows.map(\.windowNumber))
        if numbers != filteredWindows {
            filteredWindows = numbers
            engine.refreshCaptureFilter()
        }
    }

    func start() {
        cancelResume()
        beginStart()
    }

    private func beginStart() {
        guard !isRunning, !isBusy else { return }
        if LightEngine.captureProfile(for: engineConfig) != nil, !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            errorMessage = Self.screenRecordingHint
            return
        }

        isBusy = true
        errorMessage = nil
        launch()
    }

    func stop() {
        cancelResume()
        guard isRunning, !isBusy else { return }
        isBusy = true
        Task {
            await stopEngine()
            errorMessage = nil
            isBusy = false
        }
    }

    func stopEngine() async {
        _ = try? await launchTask?.value
        launchTask = nil
        await engine.stop()
        isRunning = false
        activeOutput = nil
        live.colors = []
        refreshSnapshot()
    }

    private func launch() {
        let used = settings
        let displayID = activeDisplayID
        let engine = engine
        let launch = Task { try await engine.start(displayID: displayID, output: used.output) }
        launchTask = launch
        launchFaulted = false
        Task {
            do {
                try await launch.value
                guard launchTask == launch else {
                    isBusy = false
                    return
                }
                guard !launchFaulted else {
                    await stopEngine()
                    isBusy = false
                    return
                }
                isRunning = true
                activeOutput = used.output
                if resumePending {
                    resumePending = false
                    errorMessage = nil
                }
            } catch {
                await stopEngine()
                errorMessage = error.localizedDescription
            }
            isBusy = false
            if isRunning, isAsleep {
                systemWillSleep()
                return
            }
            if isRunning, used.output != settings.output || used.displayID != settings.displayID {
                restart()
            }
        }
    }

    private func restart() {
        guard isRunning, !isBusy else { return }
        isBusy = true
        isRunning = false
        launch()
    }

    private func handleEngineFault(_ error: Error) {
        errorMessage = error.localizedDescription
        if !isRunning, isBusy { launchFaulted = true }
        guard isRunning, !isBusy else { return }
        if case let .serial(path, _)? = activeOutput, !SerialPortDiscovery.availablePorts().contains(path) {
            errorMessage = Self.controllerDisconnectedHint
            resumePending = true
            scheduleResume()
        }
        isBusy = true
        Task {
            await stopEngine()
            isBusy = false
        }
    }

    private static let controllerDisconnectedHint =
        "Controller disconnected. Aurolight turns the light back on when it's plugged in again."

    func calibrateWhite() {
        balanceBeforeCalibration = settings.whiteBalance
        isCalibratingWhite = true
    }

    func endWhiteCalibration(keep: Bool) {
        if !keep { settings.whiteBalance = balanceBeforeCalibration }
        isCalibratingWhite = false
    }

    func dismissError() {
        errorMessage = nil
        cancelResume()
    }

    private var engineConfig: LightEngine.Config {
        var config = Self.engineConfig(settings)
        if let calibrationPreview {
            config.whiteBalance = calibrationPreview
            config.testColor = RGB(r: 1, g: 1, b: 1)
        }
        return config
    }

    private static func engineConfig(_ settings: AppSettings) -> LightEngine.Config {
        .init(
            layout: settings.layout, color: settings.color, effects: settings.effects,
            whiteBalance: settings.whiteBalance)
    }

    private func settingsChanged(from old: AppSettings) {
        store.save(settings)
        engine.update(engineConfig)
        if old.displayID != settings.displayID { refreshSnapshot() }
        if old.output != settings.output { connectionTest = .idle }

        if isRunning, old.output != settings.output || old.displayID != settings.displayID { restart() }
    }
}
