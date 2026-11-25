import ABSClient
import AppFeatures
import AVFoundation
import MediaPlayer
import Observation
import PlaybackCore
import UIKit

/// Plays one Book from Audiobookshelf. The rules (timeline, skips, sleep timer, sync cadence) live in
/// `PlaybackCore` and are unit-tested there; this class only connects them to AVPlayer, the Lock Screen and the
/// server.
@Observable @MainActor
final class PlayerController {
    enum LoadState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var loadState: LoadState = .idle
    private(set) var loadedBookID: String?
    private(set) var title = ""
    private(set) var author = ""
    private(set) var cover: UIImage?
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var chapterTitle = ""
    private(set) var chapterProgress = 0.0
    private(set) var rate: Float = 1.0
    private(set) var sleepLabel: String?

    private let client: ABSClient
    private let player = AVPlayer()
    private var timeline = BookTimeline(tracks: [], chapters: [], duration: 0)
    private var session: ABSPlaySession?
    private var trackIndex = 0
    private var syncPolicy = SyncPolicy()
    private var sleepTimer = SleepTimer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var lastTick: Date?
    private var isRecovering = false
    private var remoteCommandsInstalled = false

    init(client: ABSClient) {
        self.client = client
    }

    // MARK: Loading

    func load(_ book: ABSBookSummary, deviceID: String) async {
        if loadedBookID == book.id, loadState == .ready { return }
        await stop()
        loadState = .loading
        title = book.title
        author = book.authorName ?? ""
        cover = nil
        do {
            let session = try await client.startPlayback(bookID: book.id, deviceID: deviceID)
            self.session = session
            timeline = BookTimeline(
                tracks: session.audioTracks.map { TrackSpan(start: $0.startOffset, duration: $0.duration) },
                chapters: session.chapters.map { ChapterSpan(id: $0.id, title: $0.title, start: $0.start, end: $0.end) },
                duration: session.duration)
            duration = session.duration
            loadedBookID = book.id
            syncPolicy = SyncPolicy()
            sleepTimer = SleepTimer()
            configureAudioSession()
            installObservers()
            installRemoteCommands()
            let start = SkipRules.resumeTime(saved: session.currentTime, in: timeline)
            try await openTrack(at: start, play: false)
            position = start
            refreshDerived()
            loadState = .ready
            updateNowPlaying()
            let bookID = book.id
            Task {
                let data = try? await client.coverData(bookID: bookID)
                if let data, loadedBookID == bookID {
                    cover = UIImage(data: data)
                    updateNowPlaying()
                }
            }
        } catch {
            loadedBookID = nil
            session = nil
            loadState = .failed(ABSErrorText.message(for: error))
        }
    }

    /// Opens the file that holds `time` (Book seconds), signed with the current access token.
    private func openTrack(at time: TimeInterval, play: Bool) async throws {
        guard let session, let place = timeline.locate(time), session.audioTracks.indices.contains(place.track) else {
            throw ABSError.notFound
        }
        let request = try await client.audioRequest(for: session.audioTracks[place.track])
        let asset = AVURLAsset(url: request.url, options: ["AVURLAssetHTTPHeaderFieldsKey": request.headers])
        let item = AVPlayerItem(asset: asset)
        trackIndex = place.track
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.trackEnded() }
        }
        player.replaceCurrentItem(with: item)
        await player.seek(to: CMTime(seconds: place.offset, preferredTimescale: 600),
                          toleranceBefore: .zero, toleranceAfter: .zero)
        if play {
            lastTick = Date()
            player.playImmediately(atRate: rate)
            isPlaying = true
        }
    }

    // MARK: Controls

    func play() {
        guard loadState == .ready else { return }
        configureAudioSession()
        lastTick = Date()
        player.playImmediately(atRate: rate)
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
        Task { await sendSync() }
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func skipBack() {
        seek(to: SkipRules.skippedBack(from: position, in: timeline))
    }

    func skipForward() {
        seek(to: SkipRules.skippedForward(from: position, in: timeline))
    }

    func nextChapter() {
        if let start = timeline.nextChapterStart(after: position) { seek(to: start) }
    }

    func previousChapter() {
        if let start = timeline.previousChapterStart(before: position) { seek(to: start) }
    }

    func seek(to time: TimeInterval) {
        let target = timeline.clamped(time)
        position = target
        refreshDerived()
        Task {
            if let place = timeline.locate(target), place.track == trackIndex {
                await player.seek(to: CMTime(seconds: place.offset, preferredTimescale: 600),
                                  toleranceBefore: .zero, toleranceAfter: .zero)
            } else {
                try? await openTrack(at: target, play: isPlaying)
            }
            updateNowPlaying()
        }
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        if isPlaying { player.rate = newRate }
        updateNowPlaying()
    }

    func setSleepTimer(minutes: Int) {
        sleepTimer.set(.duration(TimeInterval(minutes) * 60))
        refreshDerived()
    }

    func setSleepTimerToEndOfChapter() {
        sleepTimer.set(.endOfChapter(chapterEnd: timeline.chapter(at: position)?.end ?? duration))
        refreshDerived()
    }

    func cancelSleepTimer() {
        sleepTimer.cancel()
        refreshDerived()
    }

    /// Stops playback and closes the server session (switching Books, signing out).
    func stop() async {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        if let session {
            let report = syncPolicy.report(at: position)
            try? await client.close(sessionID: session.id, currentTime: report.currentTime,
                                    timeListened: report.timeListened)
        }
        session = nil
        loadedBookID = nil
        loadState = .idle
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Ticking, syncing, recovery

    private func tick() {
        let now = Date()
        let elapsed = lastTick.map { min(now.timeIntervalSince($0), 2) } ?? 0
        lastTick = now
        guard let item = player.currentItem else { return }
        if item.status == .failed {
            Task { await recoverFromFailure() }
            return
        }
        let offset = player.currentTime().seconds
        if offset.isFinite {
            position = timeline.globalTime(track: trackIndex, offset: offset)
        }
        isPlaying = player.timeControlStatus != .paused
        refreshDerived()
        guard isPlaying else { return }
        syncPolicy.played(elapsed)
        if sleepTimer.tick(playedSeconds: elapsed, position: position) {
            pause()
            return
        }
        if syncPolicy.isDue { Task { await sendSync() } }
        updateNowPlaying()
    }

    private func sendSync() async {
        guard let session else { return }
        let report = syncPolicy.report(at: position)
        try? await client.sync(sessionID: session.id, currentTime: report.currentTime,
                               timeListened: report.timeListened, duration: duration)
    }

    private func trackEnded() async {
        if trackIndex + 1 < timeline.tracks.count {
            try? await openTrack(at: timeline.tracks[trackIndex + 1].start, play: true)
        } else {
            position = duration
            refreshDerived()
            pause()
        }
    }

    /// The stream failed (often an expired token): reopen the file with a fresh token at the same place.
    private func recoverFromFailure() async {
        guard !isRecovering else { return }
        isRecovering = true
        defer { isRecovering = false }
        await sendSync()
        try? await openTrack(at: position, play: isPlaying)
    }

    private func refreshDerived() {
        chapterTitle = timeline.chapter(at: position)?.title ?? ""
        chapterProgress = timeline.chapterProgress(at: position)
        switch sleepTimer.mode {
        case .off:
            sleepLabel = nil
        case .duration:
            let minutes = Int(((sleepTimer.remaining ?? 0) / 60).rounded(.up))
            sleepLabel = "Sleep in \(minutes) min"
        case .endOfChapter:
            sleepLabel = "Sleep at end of chapter"
        }
    }

    // MARK: System integration

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .spokenAudio)
        try? audioSession.setActive(true)
    }

    private func installObservers() {
        if timeObserver == nil {
            timeObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 1, preferredTimescale: 1), queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
        if interruptionObserver == nil {
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] notification in
                let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard let raw, AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                Task { @MainActor in self?.pause() }
            }
        }
    }

    private func installRemoteCommands() {
        guard !remoteCommandsInstalled else { return }
        remoteCommandsInstalled = true
        SystemMedia.installRemoteCommands(for: self)
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapterTitle.isEmpty ? title : chapterTitle,
            MPMediaItemPropertyAlbumTitle: title,
            MPMediaItemPropertyArtist: author,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
        ]
        if let cover {
            info[MPMediaItemPropertyArtwork] = SystemMedia.artwork(for: cover)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

/// MediaPlayer calls these closures on its own background queues. A closure written inside a `@MainActor` type
/// inherits that isolation, and Swift 6 then traps when it runs off the main thread (this crashed the app as soon
/// as a Book started playing). So they are built here, outside the player, and hop to the main actor themselves.
private enum SystemMedia {
    nonisolated static func artwork(for image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    nonisolated static func installRemoteCommands(for player: PlayerController) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak player] _ in
            Task { @MainActor in player?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak player] _ in
            Task { @MainActor in player?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak player] _ in
            Task { @MainActor in player?.togglePlayPause() }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: SkipRules.back)]
        center.skipBackwardCommand.addTarget { [weak player] _ in
            Task { @MainActor in player?.skipBack() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: SkipRules.forward)]
        center.skipForwardCommand.addTarget { [weak player] _ in
            Task { @MainActor in player?.skipForward() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak player] _ in
            Task { @MainActor in player?.nextChapter() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak player] _ in
            Task { @MainActor in player?.previousChapter() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak player] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            Task { @MainActor in player?.seek(to: time) }
            return .success
        }
    }
}
