import AVKit
import SwiftUI

struct IntroVideoView: NSViewRepresentable {
    let url: URL
    let onFinish: @MainActor @Sendable () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let player = AVPlayer(url: url)
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = false
        context.coordinator.observe(player)
        player.play()
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        nsView.player?.pause()
        coordinator.stopObserving()
    }

    final class Coordinator {
        private let onFinish: @MainActor @Sendable () -> Void
        private var token: NSObjectProtocol?

        init(onFinish: @escaping @MainActor @Sendable () -> Void) {
            self.onFinish = onFinish
        }

        func observe(_ player: AVPlayer) {
            token = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main
            ) { [onFinish] _ in MainActor.assumeIsolated { onFinish() } }
        }

        func stopObserving() {
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
        }
    }
}
