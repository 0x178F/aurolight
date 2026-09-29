import AppKit
import SwiftUI

@main
struct AurolightApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        let model = appDelegate.model
        Window("Aurolight", id: "main") {
            MainView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 720)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 1100, height: 800)

        MenuBarExtra {
            MenuBarContent()
                .environment(model)
        } label: {
            Image(nsImage: MenuBarIcon.image(running: model.isRunning))
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var terminationReplied = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) {
            note in
            // Delivered on the main queue and used only there.
            nonisolated(unsafe) let object = note.object
            MainActor.assumeIsolated {
                guard let closing = object as? NSWindow, Self.isMainWindow(closing) else { return }
                let othersOpen = NSApp.windows.contains { $0 !== closing && Self.isMainWindow($0) && $0.isVisible }
                if !othersOpen { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.isRunning || model.isBusy else { return .terminateNow }
        Task {
            await model.stopEngine()
            replyToTermination()
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            replyToTermination()
        }
        return .terminateLater
    }

    private func replyToTermination() {
        guard !terminationReplied else { return }
        terminationReplied = true
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    static func isMainWindow(_ window: NSWindow) -> Bool {
        window.level == .normal && window.canBecomeMain
    }

    static func showMainWindow(_ open: () -> Void) {
        NSApp.setActivationPolicy(.regular)
        open()
        NSApp.activate()
    }
}
