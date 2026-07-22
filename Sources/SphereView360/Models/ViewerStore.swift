import AVFoundation
import Foundation
import os.log

private let log = OSLog(subsystem: "dev.local.SphereView360", category: "Player")

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
    private var errorLogObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var durationObserver: NSKeyValueObservation?

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
        os_log(.info, log: log, "[open] URL: %{public}@", url.absoluteString)
        os_log(.info, log: log, "[open] scheme: %{public}@, host: %{public}@, isHTTP: %{public}@",
               url.scheme ?? "nil", url.host ?? "nil",
               SupportedVideoTypes.isHTTPVideoURL(url) ? "YES" : "NO")

        guard SupportedVideoTypes.isLikelyVideo(url) else {
            os_log(.error, log: log, "[open] REJECTED: not a supported video type")
            alertMessage = "\(url.lastPathComponent) is not a supported video file."
            return
        }

        tearDownPlayer()

        os_log(.info, log: log, "[open] creating AVPlayerItem...")
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

        os_log(.info, log: log, "[open] isBuffering=%{public}@, item.status=%ld",
               isBuffering ? "YES" : "NO", item.status.rawValue)

        installObservers(for: newPlayer, item: item)
        requestViewReset()

        if !isBuffering {
            os_log(.info, log: log, "[open] local file, calling play() immediately")
            play()
        } else {
            os_log(.info, log: log, "[open] remote URL, waiting for .readyToPlay...")
        }
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else {
            os_log(.error, log: log, "[play] no player instance")
            return
        }
        os_log(.info, log: log, "[play] calling player.play(), timeControlStatus=%ld",
               player.timeControlStatus.rawValue)
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
        os_log(.info, log: log, "[obs] installing observers...")

        statusObserver = item.observe(\.status, options: [.new, .initial]) { [weak self] observedItem, change in
            let newStatus = observedItem.status
            let error = observedItem.error
            os_log(.info, log: log, "[obs] item.status -> %ld, error: %{public}@",
                   newStatus.rawValue, error?.localizedDescription ?? "nil")

            Task { @MainActor in
                self?.handleItemStatus(newStatus, error: error)
            }
        }

        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            let reason = p.reasonForWaitingToPlay
            os_log(.info, log: log, "[obs] timeControlStatus -> %ld, waitReason: %{public}@",
                   p.timeControlStatus.rawValue, reason ?? "nil")
            if p.timeControlStatus == .waitingToPlayAtSpecifiedRate, let r = reason {
                os_log(.error, log: log, "[obs] WAITING: %{public}@", r)
            }
        }

        durationObserver = item.observe(\.duration, options: [.new]) { [weak self] item, _ in
            let d = item.duration
            os_log(.info, log: log, "[obs] item.duration -> %.2fs (flags=%d, timescale=%d)",
                   d.seconds, d.flags.rawValue, d.timescale)
            Task { @MainActor in
                let seconds = d.seconds
                if seconds.isFinite, seconds > 0 {
                    self?.duration = seconds
                }
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
                os_log(.info, log: log, "[obs] didPlayToEndTime")
                self?.handlePlaybackEnded()
            }
        }

        failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            let message = error?.localizedDescription ?? "The video could not be played."
            os_log(.error, log: log, "[obs] FAILED to play to end: %{public}@",
                   error.debugDescription)

            Task { @MainActor in
                self?.alertMessage = message
                self?.pause()
            }
        }

        errorLogObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewErrorLogEntry,
            object: item,
            queue: .main
        ) { [weak self] notification in
            os_log(.error, log: log, "[obs] NEW ERROR LOG ENTRY")
            if let item = notification.object as? AVPlayerItem,
               let logData = item.errorLog() {
                let events = logData.events
                for event in events {
                    os_log(.error, log: log, "[obs]   error: %{public}@, code=%ld, uri=%{public}@",
                           event.errorComment ?? "(no comment)",
                           event.errorStatusCode,
                           event.URI ?? "(no uri)")
                }
            }
            Task { @MainActor in
                if let item = notification.object as? AVPlayerItem,
                   let events = item.errorLog()?.events.first {
                    let msg = events.errorComment ?? "Playback error"
                    self?.alertMessage = msg
                }
            }
        }

        os_log(.info, log: log, "[obs] all observers installed")
    }

    private func updatePlaybackTime(_ time: CMTime) {
        currentTime = time.seconds.isFinite ? time.seconds : 0

        let dur = player?.currentItem?.duration
        if let seconds = dur?.seconds, seconds.isFinite, seconds > 0, duration == 0 {
            os_log(.info, log: log, "[time] first duration detected: %.2fs", seconds)
            duration = seconds
        } else if let seconds = dur?.seconds, seconds.isFinite, seconds > 0 {
            duration = seconds
        }

        if player?.timeControlStatus != .playing, isPlaying {
            os_log(.info, log: log, "[time] playback stopped unexpectedly, timeControlStatus=%ld",
                   player?.timeControlStatus.rawValue ?? -1)
            isPlaying = false
        }
    }

    private func handleItemStatus(_ status: AVPlayerItem.Status, error: Error?) {
        os_log(.info, log: log, "[status] handleItemStatus: %ld, error: %{public}@, isBuffering: %{public}@",
               status.rawValue, error?.localizedDescription ?? "nil",
               isBuffering ? "YES" : "NO")

        switch status {
        case .readyToPlay:
            os_log(.info, log: log, "[status] READY TO PLAY")
            // Log available tracks
            if let tracks = player?.currentItem?.tracks {
                os_log(.info, log: log, "[status]   track count: %ld", tracks.count)
                for (i, t) in tracks.enumerated() {
                    os_log(.info, log: log, "[status]   track[%ld] type=%@, enabled=%{public}@",
                           i, t.assetTrack?.mediaType.rawValue ?? "?",
                           t.isEnabled ? "YES" : "NO")
                }
            }
            // Log presentation size
            if let size = player?.currentItem?.presentationSize {
                os_log(.info, log: log, "[status]   presentationSize: %.0fx%.0f", size.width, size.height)
            }
            guard isBuffering else {
                os_log(.info, log: log, "[status]   local file already playing, skipping")
                return
            }
            isBuffering = false
            os_log(.info, log: log, "[status]   calling play()")
            play()

        case .failed:
            isBuffering = false
            let message = error?.localizedDescription ?? "The video could not be loaded."
            os_log(.error, log: log, "[status] FAILED: %{public}@", error.debugDescription)
            if let nsErr = error as? NSError {
                os_log(.error, log: log, "[status]   domain=%{public}@, code=%ld, userInfo=%{public}@",
                       nsErr.domain, nsErr.code, nsErr.userInfo.description)
            }
            alertMessage = message

        case .unknown:
            os_log(.info, log: log, "[status] UNKNOWN (still loading)")

        @unknown default:
            os_log(.info, log: log, "[status] @unknown status: %ld", status.rawValue)
        }
    }

    private func handlePlaybackEnded() {
        os_log(.info, log: log, "[playback] ended, isLooping=%{public}@", isLooping ? "YES" : "NO")
        guard isLooping else {
            isPlaying = false
            return
        }

        seek(to: 0)
        play()
    }

    private func tearDownPlayer() {
        os_log(.info, log: log, "[teardown] removing observers...")

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

        if let errorLogObserver {
            NotificationCenter.default.removeObserver(errorLogObserver)
        }
        errorLogObserver = nil

        statusObserver?.invalidate()
        statusObserver = nil

        timeControlObserver?.invalidate()
        timeControlObserver = nil

        durationObserver?.invalidate()
        durationObserver = nil

        player?.pause()
        player = nil
        isPlaying = false
        isBuffering = false

        os_log(.info, log: log, "[teardown] done")
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
