import AVFoundation
import Foundation

@MainActor
final class ViewerStore: ObservableObject {
    @Published private(set) var currentURL: URL?
    @Published private(set) var displayName = ""
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var isLooping = true
    @Published var volume: Double = 1.0 {
        didSet {
            player?.volume = Float(volume)
        }
    }
    @Published var alertMessage: String?
    @Published private(set) var viewResetID = UUID()
    @Published private(set) var isBuffering = false

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?

    var hasVideo: Bool {
        player != nil
    }

    func openFirstSupported(_ urls: [URL]) {
        guard let url = urls.first(where: SupportedVideoTypes.isLikelyVideo) else {
            alertMessage = "No supported video file was found."
            return
        }
        open(url)
    }

    func open(_ url: URL) {
        guard SupportedVideoTypes.isLikelyVideo(url) else {
            alertMessage = "\(url.lastPathComponent) is not a supported video file."
            return
        }

        tearDownPlayer()

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.actionAtItemEnd = .none
        newPlayer.volume = Float(volume)

        currentURL = url
        displayName = SupportedVideoTypes.isHTTPVideoURL(url)
            ? url.lastPathComponent.isEmpty ? url.absoluteString : url.lastPathComponent
            : url.lastPathComponent
        player = newPlayer
        currentTime = 0
        duration = 0
        isBuffering = SupportedVideoTypes.isHTTPVideoURL(url)
        installObservers(for: newPlayer, item: item)
        requestViewReset()

        if !isBuffering {
            play()
        }
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else {
            return
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func seek(to seconds: Double) {
        guard let player else {
            return
        }

        let boundedSeconds = max(0, min(seconds, duration > 0 ? duration : seconds))
        player.seek(
            to: CMTime(seconds: boundedSeconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        currentTime = boundedSeconds
    }

    func requestViewReset() {
        viewResetID = UUID()
    }

    private func installObservers(for player: AVPlayer, item: AVPlayerItem) {
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            Task { @MainActor in
                self?.handleItemStatus(observedItem.status, error: observedItem.error)
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.updatePlaybackTime(time)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePlaybackEnded()
            }
        }

        failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription ?? "The video could not be played."

            Task { @MainActor in
                self?.alertMessage = message
                self?.pause()
            }
        }
    }

    private func updatePlaybackTime(_ time: CMTime) {
        currentTime = time.seconds.isFinite ? time.seconds : 0

        if let itemDuration = player?.currentItem?.duration.seconds, itemDuration.isFinite {
            duration = itemDuration
        }

        if player?.timeControlStatus != .playing, isPlaying {
            isPlaying = false
        }
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status, error: Error?) {
        switch status {
        case .readyToPlay:
            guard isBuffering else {
                return
            }
            isBuffering = false
            play()

        case .failed:
            isBuffering = false
            let message = error?.localizedDescription ?? "The video could not be loaded."
            alertMessage = message

        case .unknown:
            break

        @unknown default:
            break
        }
    }

    private func handlePlaybackEnded() {
        guard isLooping else {
            isPlaying = false
            return
        }

        seek(to: 0)
        play()
    }

    private func tearDownPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil

        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
        }
        failedObserver = nil

        statusObserver?.invalidate()
        statusObserver = nil

        player?.pause()
        player = nil
        isPlaying = false
        isBuffering = false
    }
}

#if os(macOS)
extension ViewerStore {
    func presentOpenPanel() {
        guard let url = VideoOpenPanel.chooseVideo() else {
            return
        }
        open(url)
    }

    func registerOpenWithOption() {
        do {
            try OpenWithRegistrationService.registerCurrentAppBundle()
            alertMessage = "SphereView360 was registered as an Open With option. It was not made the default app for MP4, MOV, or M4V files."
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}
#endif
