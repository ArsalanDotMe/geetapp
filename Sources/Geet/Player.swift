import AppKit
import AVFoundation
import MediaPlayer
import Combine
import GeetCore

@MainActor
final class PlayerClock: ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0
}

@MainActor
final class Player: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var collectionID: String?
    @Published private(set) var collectionTitle = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSleeping = false
    @Published var error: String?
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume: Float = 0.8 { didSet { media?.volume = volume } }
    let clock = PlayerClock()
    var automaticCache = false
    var offlineEnabled = false
    var onSnapshot: ((String, Int, Double) -> Void)?
    var onConfiguration: (() -> Void)?
    var onTrackChanged: ((Track) -> Void)?
    private(set) var media: AVPlayer?
    private var collection: Collection?
    private var queue = PlaybackQueue()
    private var position = 0.0
    private var duration = 0.0
    private var visible = false
    private var periodic: Any?
    private var statusObservation: NSKeyValueObservation?
    private var controlObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var stallObserver: NSObjectProtocol?
    private var loader: MediaResourceLoader?
    private var resolveTask: Task<Void, Never>?
    private var lookAhead: Task<Void, Never>?
    private var idleTimer: DispatchSourceTimer?
    private var generation = UUID()
    private var recovery = RecoveryBudget()
    private var recovering = false
    private let resolver: Resolver
    private let cache: MediaCache
    private let idleDelay: TimeInterval
    private let enablesMediaCommands: Bool
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var commands: [(MPRemoteCommand, Any)] = []
    var hasProgressObserver: Bool { periodic != nil }
    var hasMediaPipeline: Bool { media != nil }
    var currentIndex: Int? { queue.current }

    init(resolver: Resolver, cache: MediaCache, idleDelay: TimeInterval = 600, mediaCommands: Bool = true) {
        self.resolver = resolver; self.cache = cache; self.idleDelay = idleDelay; self.enablesMediaCommands = mediaCommands
    }

    func play(_ collection: Collection, index: Int? = nil, fromBeginning: Bool = false) {
        if self.collectionID == collection.id, index == nil, !fromBeginning {
            toggle(); return
        }
        snapshot()
        self.collection = collection; collectionID = collection.id; collectionTitle = collection.title
        let start = index ?? (fromBeginning ? 0 : collection.resumeIndex)
        queue.reset(count: collection.tracks.count, start: start, shuffled: shuffle)
        guard let current = queue.current else { return }
        let offset = fromBeginning || index != nil ? 0 : collection.resumePosition
        recovery.reset(collection.tracks[current].id)
        load(collection.tracks[current], at: offset)
    }

    func toggle() {
        if isPlaying || isLoading { pause() } else { resume() }
    }
    func pause() {
        resolveTask?.cancel(); resolveTask = nil; generation = UUID()
        lookAhead?.cancel(); lookAhead = nil
        Task { await resolver.cancelBackground() }
        media?.pause(); isPlaying = false; isLoading = false
        snapshot(); publishNowPlaying(); stopProgressObserver()
        cancelIdleDeadline()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + idleDelay, leeway: .milliseconds(Int(min(1_000, idleDelay * 50))))
        timer.setEventHandler { [weak self] in self?.enterDeepIdle() }
        timer.resume(); idleTimer = timer
    }
    func resume() {
        guard let track else { return }
        error = nil; cancelIdleDeadline()
        if media != nil {
            media?.play(); isPlaying = true; isSleeping = false
            if visible { startProgressObserver() }; publishNowPlaying(); prefetchNext()
        } else { load(track, at: position) }
    }
    func next(automatic: Bool = false) {
        snapshot()
        guard let index = queue.moveNext(repeatMode: repeatMode, automatic: automatic), let collection else {
            seek(0); pause(); return
        }
        if !automatic { recovery.reset(collection.tracks[index].id) }
        load(collection.tracks[index], at: 0)
    }
    func previous() {
        let current = media?.currentTime().seconds ?? position
        if current.isFinite && current > 3 && track?.isLive != true { seek(0); return }
        snapshot()
        guard let index = queue.movePrevious(), let collection else { return }
        recovery.reset(collection.tracks[index].id); load(collection.tracks[index], at: 0)
    }
    func seek(_ value: Double) {
        guard track?.isLive != true else { return }
        position = max(0, min(value, duration > 0 ? duration : value))
        media?.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        clock.position = position; snapshot(); publishNowPlaying()
    }
    func toggleShuffle() {
        shuffle.toggle()
        if let collection { queue.reset(count: collection.tracks.count, start: queue.current ?? 0, shuffled: shuffle) }
        lookAhead?.cancel(); if isPlaying { prefetchNext() }; onConfiguration?()
    }
    func cycleRepeat() { repeatMode = repeatMode.next; onConfiguration?() }

    func panelVisible(_ value: Bool) {
        visible = value
        if value { updateClock(); if isPlaying { startProgressObserver() } }
        else { stopProgressObserver(); snapshot() }
    }
    func snapshot() {
        if let seconds = media?.currentTime().seconds, seconds.isFinite { position = seconds }
        if let collectionID, let index = queue.current { onSnapshot?(collectionID, index, position) }
    }
    func enterDeepIdle() {
        guard !isPlaying, !isLoading else { return }
        cancelIdleDeadline(); snapshot(); tearDownPipeline(); isSleeping = true
        publishNowPlaying()
    }
    func shutdown() {
        snapshot(); resolveTask?.cancel(); lookAhead?.cancel(); cancelIdleDeadline(); tearDownPipeline()
        for (command, target) in commands { command.removeTarget(target) }; commands.removeAll()
        if track != nil { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
    }
    func setArtwork(_ image: NSImage, trackID: String) {
        guard track?.id == trackID else { return }
        nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        publishNowPlaying()
    }

    private func load(_ track: Track, at offset: Double, recoveryAttempt: Bool = false) {
        if enablesMediaCommands && commands.isEmpty { installMediaCommands() }
        resolveTask?.cancel(); lookAhead?.cancel(); cancelIdleDeadline()
        tearDownPipeline()
        let token = UUID(); generation = token
        self.track = track; nowPlayingArtwork = nil; position = max(0, offset); duration = track.duration ?? 0
        clock.position = position; clock.duration = duration
        error = nil; isLoading = true; isPlaying = false; isSleeping = false
        resolveTask = Task { [weak self] in
            guard let self else { return }
            do {
                await resolver.cancelBackground()
                let item: AVPlayerItem
                if offlineEnabled, let saved = await cache.completedEntry(for: track.id) {
                    let resource = MediaResourceLoader(cache: cache, key: saved.key, stream: nil)
                    loader = resource; item = AVPlayerItem(asset: resource.asset())
                } else {
                    let stream = try await resolver.resolve(track, fresh: recoveryAttempt)
                    try Task.checkCancellation()
                    guard generation == token else { return }
                    self.track = stream.track; duration = stream.track.duration ?? duration
                    if automaticCache && offlineEnabled && !stream.isHLS && !stream.track.isLive {
                        let key = MediaCache.key(trackID: track.id, formatID: stream.formatID)
                        let resource = MediaResourceLoader(cache: cache, key: key, stream: stream)
                        loader = resource; item = AVPlayerItem(asset: resource.asset())
                    } else {
                        let asset = AVURLAsset(url: stream.url, options: ["AVURLAssetHTTPHeaderFieldsKey": stream.headers])
                        item = AVPlayerItem(asset: asset)
                    }
                }
                try Task.checkCancellation(); guard generation == token else { return }
                let player = AVPlayer(playerItem: item)
                player.volume = volume; player.automaticallyWaitsToMinimizeStalling = true
                item.preferredForwardBufferDuration = track.isLive ? 10 : 20
                media = player
                observe(item, player: player)
                if position > 0 && self.track?.isLive != true { await player.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
                try Task.checkCancellation(); guard generation == token else { return }
                player.play(); isPlaying = true; isLoading = false; recovering = false
                if let track = self.track { onTrackChanged?(track) }
                if visible { startProgressObserver() }
                publishNowPlaying(); prefetchNext()
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                self.error = error.localizedDescription; isLoading = false; isPlaying = false; recovering = false
                tearDownPipeline(); publishNowPlaying()
            }
        }
    }
    private func observe(_ item: AVPlayerItem, player: AVPlayer) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.media?.currentItem === item else { return }
                if item.status == .failed { self.recover(item.error?.localizedDescription ?? "Playback was interrupted.") }
                else if item.status == .readyToPlay {
                    for itemTrack in item.tracks where itemTrack.assetTrack?.mediaType == .video { itemTrack.isEnabled = false }
                    let value = item.duration.seconds
                    if value.isFinite && value > 0 { self.duration = value; self.clock.duration = value }
                    self.publishNowPlaying()
                }
            }
        }
        controlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, self.media === player else { return }
                self.isLoading = player.timeControlStatus == .waitingToPlayAtSpecifiedRate && self.isPlaying
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.next(automatic: true) }
        }
        stallObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.recover("The stream was interrupted.") }
        }
    }
    private func recover(_ message: String) {
        guard !recovering, isPlaying, let track else { return }
        guard recovery.permit(track.id) else { pause(); enterDeepIdle(); error = "Playback stopped after two recovery attempts. \(message)"; return }
        recovering = true; snapshot(); load(track, at: position, recoveryAttempt: true)
    }
    private func prefetchNext() {
        lookAhead?.cancel()
        guard isPlaying, let index = queue.peekNext(repeatMode: repeatMode), let collection,
              collection.tracks.indices.contains(index), collection.tracks[index].id != track?.id else { return }
        let next = collection.tracks[index]
        lookAhead = Task { [resolver] in _ = try? await resolver.resolve(next, priority: .background) }
    }
    private func startProgressObserver() {
        guard visible, periodic == nil, let media, isPlaying else { return }
        periodic = media.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self, self.visible else { return }; self.updateClock() }
        }
    }
    private func stopProgressObserver() {
        if let periodic { media?.removeTimeObserver(periodic); self.periodic = nil }
    }
    private func updateClock() {
        if let value = media?.currentTime().seconds, value.isFinite { position = value }
        clock.position = position; clock.duration = duration
    }
    private func tearDownPipeline() {
        stopProgressObserver(); statusObservation = nil; controlObservation = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }; endObserver = nil
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }; stallObserver = nil
        media?.pause(); media?.replaceCurrentItem(with: nil); media = nil
        loader?.cancel(); loader = nil
    }
    private func cancelIdleDeadline() {
        idleTimer?.setEventHandler(handler: nil); idleTimer?.cancel(); idleTimer = nil
    }
    private func publishNowPlaying() {
        guard let track else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: collectionTitle, MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: track.isLive,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let nowPlayingArtwork { info[MPMediaItemPropertyArtwork] = nowPlayingArtwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
    private func installMediaCommands() {
        let center = MPRemoteCommandCenter.shared()
        func register(_ command: MPRemoteCommand, _ action: @escaping @MainActor () -> Void) {
            command.isEnabled = true
            let target = command.addTarget { _ in Task { @MainActor in action() }; return .success }
            commands.append((command, target))
        }
        register(center.playCommand) { [weak self] in self?.resume() }
        register(center.pauseCommand) { [weak self] in self?.pause() }
        register(center.togglePlayPauseCommand) { [weak self] in self?.toggle() }
        register(center.nextTrackCommand) { [weak self] in self?.next() }
        register(center.previousTrackCommand) { [weak self] in self?.previous() }
        let target = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(event.positionTime) }; return .success
        }
        commands.append((center.changePlaybackPositionCommand, target))
    }
}
