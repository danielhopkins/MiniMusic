import Foundation
import MusicKit
import Combine
import Observation

@Observable final class PlayerViewModel {

    // MARK: - State

    private(set) var currentTitle: String = ""
    private(set) var currentArtist: String = ""
    private(set) var currentAlbumTitle: String = ""
    private(set) var artwork: Artwork?
    private(set) var isPlaying: Bool = false
    private(set) var playbackTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    // Classical metadata (populated when the current item is a classical work)
    private(set) var currentComposer: String = ""
    private(set) var currentWorkName: String = ""
    private(set) var currentMovementName: String = ""
    private(set) var currentMovementNumber: Int?
    private(set) var currentMovementCount: Int?
    private(set) var currentGenres: [String] = []

    /// True when the current item is a classical work. The genre is the primary
    /// signal — Apple Music reliably tags these "Classical" — which catches
    /// standalone pieces (overtures, single-movement works) that carry a
    /// composer but no `workName`/`movementName`. The work/movement checks are a
    /// fallback for anything tagged under a different genre.
    var isClassical: Bool {
        currentGenres.contains { $0.localizedCaseInsensitiveContains("classical") }
            || !currentWorkName.isEmpty
            || !currentMovementName.isEmpty
    }

    // MARK: - Playback Source

    /// The album/playlist/station the current queue was started from, or `nil`
    /// when playing loose songs. Drives the "Playing from …" card and its
    /// library actions.
    private(set) var playbackSource: PlaybackSource?
    /// True once the source is in the library — either because it started there
    /// or because the user just added it. Gates the "Add to Library" action.
    private(set) var isSourceInLibrary = false
    /// True once the user has favorited the source this session.
    private(set) var isSourceFavorited = false
    /// User-facing message from the most recent source action, if it failed.
    private(set) var sourceActionError: String?
    /// Real catalog artwork resolved for a library playlist that originated from
    /// Apple Music, since its own library artwork won't render. `nil` until (and
    /// unless) resolution succeeds.
    private(set) var resolvedSourceArtwork: Artwork?

    /// The artwork to show for the current source: a resolved catalog cover when
    /// we have one, otherwise the source's best-available artwork (falling back
    /// to the now-playing track for library playlists).
    var sourceArtwork: Artwork? {
        guard let source = playbackSource else { return nil }
        return resolvedSourceArtwork ?? source.displayArtwork(nowPlaying: artwork)
    }

    /// True while a live radio broadcast is playing. A live stream has no
    /// duration, no seekable position, and nothing to skip to, so the transport
    /// UI has to drop its scrubber and skip controls rather than show dead ones.
    var isLiveStation: Bool {
        guard case .station(let station) = playbackSource else { return false }
        return station.isLive
    }

    // MARK: - Queue Access

    var queueEntries: [ApplicationMusicPlayer.Queue.Entry] {
        Array(player.queue.entries)
    }

    var currentQueueEntry: ApplicationMusicPlayer.Queue.Entry? {
        player.queue.currentEntry
    }

    var queueCount: Int {
        max(player.queue.entries.count - 1, 0)
    }

    /// Composer names for queue rows, keyed by song ID `rawValue`. MusicKit's
    /// queue entries don't carry composers, so a classical row would otherwise
    /// show only the performer. Populated in bulk by `refreshQueueComposers()`.
    private(set) var queueComposers: [String: String] = [:]

    /// The resolved composer for a queue entry, or `nil` when the entry isn't a
    /// song or its composer hasn't been fetched (e.g. a non-classical track).
    func composer(for entry: ApplicationMusicPlayer.Queue.Entry) -> String? {
        guard case let .song(song) = entry.item else { return nil }
        return queueComposers[song.id.rawValue]
    }

    /// Resolves composers for the whole queue in one batched pass. Entries that
    /// already carry a composer are used directly; the rest are fetched from the
    /// catalog/library in chunked requests (via `fetchSongs`), so a long queue
    /// costs a couple of round-trips rather than one per row. Song IDs are only
    /// looked up once, so non-classical tracks aren't re-fetched as the queue
    /// changes.
    func refreshQueueComposers() {
        var resolved = queueComposers
        var missing: [String] = []
        for entry in player.queue.entries {
            guard case let .song(song) = entry.item else { continue }
            let key = song.id.rawValue
            if resolved[key] != nil || queueComposerAttempted.contains(key) { continue }
            if let name = song.composerName, !name.isEmpty {
                resolved[key] = name
                queueComposerAttempted.insert(key)
            } else {
                missing.append(key)
            }
        }
        if resolved.count != queueComposers.count { queueComposers = resolved }
        guard !missing.isEmpty else { return }

        queueComposerTask?.cancel()
        queueComposerTask = Task { [weak self] in
            let songs = await Self.fetchSongs(for: missing)
            guard !Task.isCancelled, let self else { return }
            var found: [String: String] = [:]
            for song in songs {
                // Mark every fetched ID attempted, so tracks with no composer
                // (i.e. non-classical) aren't looked up again. IDs the request
                // couldn't resolve stay eligible for a later retry.
                self.queueComposerAttempted.insert(song.id.rawValue)
                if let name = song.composerName, !name.isEmpty {
                    found[song.id.rawValue] = name
                }
            }
            guard !found.isEmpty else { return }
            self.queueComposers.merge(found) { _, new in new }
        }
    }

    // MARK: - Private

    nonisolated(unsafe) private let player = ApplicationMusicPlayer.shared
    private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var timeObserverTask: Task<Void, Never>?
    @ObservationIgnored private var metadataFetchTask: Task<Void, Never>?
    @ObservationIgnored private var sourceArtworkTask: Task<Void, Never>?
    /// ID of the item the displayed metadata belongs to, so a late catalog
    /// fetch can be discarded if the track has already changed.
    @ObservationIgnored private var currentItemID: MusicItemID?
    /// Song IDs already looked up for a composer (found or not), so a queue full
    /// of non-classical tracks isn't re-fetched on every queue change.
    @ObservationIgnored private var queueComposerAttempted: Set<String> = []
    @ObservationIgnored private var queueComposerTask: Task<Void, Never>?

    // Queue persistence
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    @ObservationIgnored private var restoreStarted = false
    /// Persistence is gated until a restore has been attempted so the empty
    /// queue at launch doesn't overwrite the saved snapshot before we restore.
    @ObservationIgnored private var restoreCompleted = false
    @ObservationIgnored private var persistTickCounter = 0
    /// Position to seek to the first time playback starts after a restore.
    /// MusicKit only honors a seek once playback has begun, so we defer the
    /// restored position until the user presses play (no audio/seek on launch).
    @ObservationIgnored private var pendingResumeTime: TimeInterval?

    // MARK: - Init

    init() {
        observePlaybackState()
        observeCurrentEntry()
        startTimeObserver()
    }

    deinit {
        timeObserverTask?.cancel()
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        if isPlaying {
            Task { player.pause() }
            return
        }
        // The queue can end up empty while a source is still remembered (e.g.
        // playback ran to the end, or the system player was cleared elsewhere).
        // In that case, restart from the remembered source rather than no-op.
        if player.queue.entries.isEmpty, let source = playbackSource {
            replay(source)
            return
        }
        Task {
            try? await player.play()
            applyPendingResumeIfNeeded()
        }
    }

    /// Restarts playback from a remembered source, reusing the same entry point
    /// (and shuffle behavior) the source was originally played with.
    private func replay(_ source: PlaybackSource) {
        switch source {
        case .album(let album, let isLibrary):
            play(album, isLibrary: isLibrary)
        case .playlist(let playlist, let isLibrary):
            playPlaylist(playlist, isLibrary: isLibrary)
        case .station(let station):
            play(station)
        }
    }

    func skipForward() {
        pendingResumeTime = nil
        Task {
            try? await player.skipToNextEntry()
        }
    }

    func skipBackward() {
        pendingResumeTime = nil
        Task {
            try? await player.skipToPreviousEntry()
        }
    }

    func seek(to time: TimeInterval) {
        pendingResumeTime = nil
        player.playbackTime = time
    }

    /// After a restore, the first `play()` seeks to the saved position. MusicKit
    /// honors a seek only once playback has started, so this runs post-`play()`.
    private func applyPendingResumeIfNeeded() {
        guard let resume = pendingResumeTime else { return }
        pendingResumeTime = nil
        player.playbackTime = resume
    }

    // MARK: - Queue Management

    func play(_ song: Song) {
        setSource(nil)
        Task {
            player.queue = [song]
            try? await player.play()
        }
    }

    func play(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        setSource(nil)
        Task {
            player.queue = ApplicationMusicPlayer.Queue(for: songs)
            try? await player.play()
        }
    }

    func play(_ album: Album, isLibrary: Bool = false) {
        setSource(.album(album, isLibrary: isLibrary))
        Task {
            player.queue = [album]
            try? await player.play()
        }
    }

    func playPlaylist(_ playlist: Playlist, isLibrary: Bool = false) {
        setSource(.playlist(playlist, isLibrary: isLibrary))
        Task {
            player.state.shuffleMode = .songs
            player.queue = [playlist]
            try? await player.prepareToPlay()
            try? await player.play()
        }
    }

    func play(_ station: Station) {
        setSource(.station(station))
        Task {
            player.queue = [station]
            try? await player.play()
        }
    }

    func playTopSongForArtist(_ artist: Artist) {
        setSource(nil)
        Task {
            do {
                let detailedArtist = try await artist.with([.topSongs])
                guard let topSong = detailedArtist.topSongs?.first else {
                    return
                }
                player.queue = [topSong]
                try await player.play()
            } catch {
                // Artist playback error - non-fatal
            }
        }
    }

    func playItem(_ item: SearchResultItem) {
        switch item {
        case .librarySong(let song), .catalogSong(let song):
            play(song)
        case .libraryAlbum(let album):
            play(album, isLibrary: true)
        case .catalogAlbum(let album):
            play(album, isLibrary: false)
        case .libraryArtist(let artist), .catalogArtist(let artist):
            playTopSongForArtist(artist)
        case .libraryPlaylist(let playlist):
            playPlaylist(playlist, isLibrary: true)
        case .catalogPlaylist(let playlist):
            playPlaylist(playlist, isLibrary: false)
        case .catalogStation(let station):
            play(station)
        }
    }

    // MARK: - Playback Source Actions

    /// Sets the current source and resets the per-source action state. A source
    /// that already lives in the library starts out marked as such so its
    /// "Add to Library" action reads as already-added.
    private func setSource(_ source: PlaybackSource?) {
        playbackSource = source
        isSourceInLibrary = source?.isInLibrary ?? false
        isSourceFavorited = false
        sourceActionError = nil
        resolvedSourceArtwork = nil
        resolveSourceArtworkIfNeeded(source)
    }

    /// A library playlist added from Apple Music has a catalog counterpart whose
    /// cover actually renders. Resolve it in the background and swap it in for
    /// display. Only library playlists need this; albums and catalog playlists
    /// already carry a usable cover.
    private func resolveSourceArtworkIfNeeded(_ source: PlaybackSource?) {
        sourceArtworkTask?.cancel()
        guard case .playlist(let playlist, true)? = source else { return }
        sourceArtworkTask = Task { [weak self] in
            guard let catalogID = Self.catalogID(from: playlist),
                  let catalog = await Self.fetchPlaylist(id: catalogID, isLibrary: false),
                  let artwork = catalog.artwork
            else { return }
            guard !Task.isCancelled, let self,
                  case .playlist(let current, true)? = self.playbackSource,
                  current.id == playlist.id
            else { return }
            self.resolvedSourceArtwork = artwork
        }
    }

    /// Extracts the Apple Music catalog ID from a library playlist's play
    /// parameters, present only when the playlist originated from the catalog
    /// (i.e. was added/favorited rather than user-created). `playParameters` is
    /// opaque but `Codable`, so round-trip it through JSON to read the field.
    private nonisolated static func catalogID(from playlist: Playlist) -> String? {
        guard let params = playlist.playParameters,
              let data = try? JSONEncoder().encode(params),
              let decoded = try? JSONDecoder().decode(PlayParametersFields.self, from: data)
        else { return nil }
        return decoded.globalID ?? decoded.catalogID
    }

    nonisolated private struct PlayParametersFields: Decodable {
        let globalID: String?
        let catalogID: String?

        enum CodingKeys: String, CodingKey {
            case globalID = "globalId"
            case catalogID = "catalogId"
        }
    }

    /// Adds the current album/playlist source to the user's library. Only catalog
    /// sources reach here — library sources have the action disabled.
    func addSourceToLibrary() async {
        guard let source = playbackSource else { return }
        sourceActionError = nil
        do {
            try await Self.addToLibrary(source)
            isSourceInLibrary = true
        } catch {
            sourceActionError = "Couldn't add to library."
        }
    }

    /// Issues a `POST …/me/library?ids[{type}]={id}`. `MusicLibrary.add` is
    /// iOS-only, so on macOS we hit the Apple Music API directly; the endpoint
    /// takes catalog IDs, which is all this action is offered for.
    private nonisolated static func addToLibrary(_ source: PlaybackSource) async throws {
        let type: String
        let id: String
        switch source {
        case .album(let album, _):
            type = "albums"
            id = album.id.rawValue
        case .playlist(let playlist, _):
            type = "playlists"
            id = playlist.id.rawValue
        case .station:
            return
        }

        var components = URLComponents(string: "https://api.music.apple.com/v1/me/library")
        components?.queryItems = [URLQueryItem(name: "ids[\(type)]", value: id)]
        guard let url = components?.url else { throw SourceActionError.invalidRequest }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = try await MusicDataRequest(urlRequest: request).response()
    }

    /// Favorites (loves) the current source via the Apple Music ratings API,
    /// which MusicKit doesn't wrap with a typed method.
    func favoriteSource() async {
        guard let source = playbackSource else { return }
        sourceActionError = nil
        do {
            try await Self.favorite(source)
            isSourceFavorited = true
        } catch {
            sourceActionError = "Couldn't favorite."
        }
    }

    /// Issues a `PUT …/me/ratings/{type}/{id}` with a value of `1` (love).
    /// Library items use the `library-*` rating types; catalog items the plain
    /// ones. `MusicDataRequest` attaches the developer and user tokens.
    private nonisolated static func favorite(_ source: PlaybackSource) async throws {
        let type: String
        let id: String
        switch source {
        case .album(let album, let isLibrary):
            type = isLibrary ? "library-albums" : "albums"
            id = album.id.rawValue
        case .playlist(let playlist, let isLibrary):
            type = isLibrary ? "library-playlists" : "playlists"
            id = playlist.id.rawValue
        case .station:
            return
        }

        guard let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.music.apple.com/v1/me/ratings/\(type)/\(encodedID)")
        else {
            throw SourceActionError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "type": "rating",
            "attributes": ["value": 1],
        ])

        _ = try await MusicDataRequest(urlRequest: request).response()
    }

    enum SourceActionError: Error {
        case invalidRequest
    }

    func addToQueue(_ song: Song) {
        Task { await Self.enqueue(song) }
    }

    /// `ApplicationMusicPlayer.Queue.insert` is a `@concurrent` method on a
    /// non-Sendable `Queue`, so it can't be called with a main-actor-isolated
    /// queue value. Access the shared player off the main actor instead.
    private nonisolated static func enqueue(_ song: Song) async {
        try? await ApplicationMusicPlayer.shared.queue.insert(song, position: .tail)
    }

    // MARK: - Observation

    private func observePlaybackState() {
        player.state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.isPlaying = self.player.state.playbackStatus == .playing
            }
            .store(in: &cancellables)
    }

    private func observeCurrentEntry() {
        player.queue.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    self.updateCurrentEntry()
                    self.refreshQueueComposers()
                }
            }
            .store(in: &cancellables)
    }

    private func updateCurrentEntry() {
        guard let entry = player.queue.currentEntry else {
            currentTitle = ""
            currentArtist = ""
            currentAlbumTitle = ""
            artwork = nil
            duration = 0
            currentItemID = nil
            metadataFetchTask?.cancel()
            clearClassicalMetadata()
            return
        }

        currentTitle = entry.title
        // A live stream puts its whole metadata string in both fields, so the
        // subtitle would just repeat the title back under it.
        let subtitle = entry.subtitle ?? ""
        currentArtist = subtitle == entry.title ? "" : subtitle
        artwork = entry.artwork

        // Read full song metadata for album title, duration, and classical fields
        if case let .song(song) = entry.item {
            currentAlbumTitle = song.albumTitle ?? ""
            duration = song.duration ?? 0
            currentItemID = song.id
            applyClassicalMetadata(from: song)
            // Queue entries often arrive without classical attributes hydrated
            // (composer/work/movement), so refresh from the catalog by ID.
            fetchClassicalMetadata(for: song.id)
        } else {
            currentAlbumTitle = ""
            duration = 0
            currentItemID = nil
            metadataFetchTask?.cancel()
            clearClassicalMetadata()
        }

        schedulePersist()
    }

    private func applyClassicalMetadata(from song: Song) {
        currentComposer = song.composerName ?? ""
        currentWorkName = song.workName ?? ""
        currentMovementName = song.movementName ?? ""
        currentMovementNumber = song.movementNumber
        currentMovementCount = song.movementCount
        currentGenres = song.genreNames
    }

    /// Fetches the full catalog `Song` so classical attributes (work, movement,
    /// composer) are available even when the queue entry didn't carry them.
    /// Skips library items, whose IDs aren't valid catalog identifiers.
    private func fetchClassicalMetadata(for id: MusicItemID) {
        metadataFetchTask?.cancel()
        metadataFetchTask = Task { [weak self] in
            do {
                let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: id)
                let response = try await request.response()
                guard !Task.isCancelled, let self, let song = response.items.first else { return }
                // Discard if the track changed while the fetch was in flight.
                guard self.currentItemID == id else { return }
                self.applyClassicalMetadata(from: song)
            } catch {
                // Non-fatal: keep whatever the queue entry provided.
            }
        }
    }

    private func clearClassicalMetadata() {
        currentComposer = ""
        currentWorkName = ""
        currentMovementName = ""
        currentMovementNumber = nil
        currentMovementCount = nil
        currentGenres = []
    }

    private func startTimeObserver() {
        timeObserverTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // While a restore is pending (paused, not yet played), keep
                // showing the saved position instead of the player's 0.
                if let pending = self.pendingResumeTime, !self.isPlaying {
                    self.playbackTime = pending
                } else {
                    // A live stream reports a NaN playback time, which would
                    // otherwise reach the progress Slider's value binding.
                    let time = self.player.playbackTime
                    self.playbackTime = time.isFinite ? time : 0
                }
                // Persist the playback position roughly every 5s while playing
                // so resume lands near where we left off.
                self.persistTickCounter += 1
                if self.persistTickCounter >= 10, self.isPlaying {
                    self.persistTickCounter = 0
                    self.persistQueue()
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    // MARK: - Queue Persistence

    /// Debounced snapshot save, used when the queue or current entry changes.
    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.persistQueue()
        }
    }

    /// Captures the current queue (song entries only) and playback position.
    /// No-op until a restore has been attempted, so the empty launch queue
    /// can't clobber the saved snapshot before it's restored.
    func persistQueue() {
        guard restoreCompleted else { return }
        // A station's queue holds one opaque live entry with no underlying song,
        // so it would collect no IDs and clear the snapshot. Radio is a detour,
        // not a new queue — leave the saved one intact to come back to.
        if case .station = playbackSource { return }

        let currentEntryID = player.queue.currentEntry?.id
        var ids: [String] = []
        var currentIndex = 0
        for entry in player.queue.entries {
            guard case let .song(song) = entry.item else { continue }
            if entry.id == currentEntryID { currentIndex = ids.count }
            ids.append(song.id.rawValue)
        }

        guard !ids.isEmpty else {
            QueuePersistence.clear()
            return
        }

        // Before the deferred resume is applied, `player.playbackTime` is 0, so
        // persist the pending position to avoid losing it.
        let time = pendingResumeTime ?? player.playbackTime
        QueuePersistence.save(
            QueueSnapshot(
                songIDs: ids,
                currentIndex: currentIndex,
                playbackTime: time,
                source: sourceSnapshot
            )
        )
    }

    /// A serializable descriptor of the current source, or `nil` for loose songs
    /// and stations (which can't be reliably rehydrated by ID).
    private var sourceSnapshot: SourceSnapshot? {
        switch playbackSource {
        case .album(let album, let isLibrary):
            return SourceSnapshot(kind: .album, id: album.id.rawValue, isLibrary: isLibrary)
        case .playlist(let playlist, let isLibrary):
            return SourceSnapshot(kind: .playlist, id: playlist.id.rawValue, isLibrary: isLibrary)
        case .station, .none:
            return nil
        }
    }

    /// Rebuilds the saved queue on launch (paused; the saved position is
    /// applied when the user first presses play). Safe to call more than once;
    /// only the first authorized call with an empty player queue does work.
    /// Retries on a later call if MusicKit isn't authorized yet.
    func restoreQueueIfNeeded() async {
        guard !restoreStarted else { return }
        guard MusicAuthorization.currentStatus == .authorized else { return }
        restoreStarted = true

        defer { restoreCompleted = true }

        guard player.queue.entries.isEmpty, let snapshot = QueuePersistence.load() else { return }

        let songs = await Self.fetchSongs(for: snapshot.songIDs)
        // Bail if the user started playing something while we were fetching.
        guard !songs.isEmpty, player.queue.entries.isEmpty else { return }

        let currentID = snapshot.songIDs.indices.contains(snapshot.currentIndex)
            ? snapshot.songIDs[snapshot.currentIndex]
            : nil
        let startSong = songs.first { $0.id.rawValue == currentID } ?? songs.first

        player.queue = ApplicationMusicPlayer.Queue(for: songs, startingAt: startSong)
        // Defer the seek until the user presses play — MusicKit won't honor a
        // seek on a prepared-but-not-started queue. Show the saved position in
        // the meantime so the progress bar reflects where playback will resume.
        if snapshot.playbackTime > 1 {
            pendingResumeTime = snapshot.playbackTime
            playbackTime = snapshot.playbackTime
        }
        try? await player.prepareToPlay()
        updateCurrentEntry()
        await restoreSource(snapshot.source)
    }

    /// Rehydrates the persisted source by ID so "Playing from …" and its library
    /// actions come back on relaunch. Best-effort: a failed fetch just leaves the
    /// source unset.
    private func restoreSource(_ snapshot: SourceSnapshot?) async {
        guard let snapshot else { return }
        switch snapshot.kind {
        case .album:
            if let album = await Self.fetchAlbum(id: snapshot.id, isLibrary: snapshot.isLibrary) {
                setSource(.album(album, isLibrary: snapshot.isLibrary))
            }
        case .playlist:
            if let playlist = await Self.fetchPlaylist(id: snapshot.id, isLibrary: snapshot.isLibrary) {
                setSource(.playlist(playlist, isLibrary: snapshot.isLibrary))
            }
        }
    }

    private nonisolated static func fetchAlbum(id: String, isLibrary: Bool) async -> Album? {
        do {
            if isLibrary {
                var request = MusicLibraryRequest<Album>()
                request.filter(matching: \.id, equalTo: MusicItemID(id))
                return try await request.response().items.first
            }
            let request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: MusicItemID(id))
            return try await request.response().items.first
        } catch {
            return nil
        }
    }

    private nonisolated static func fetchPlaylist(id: String, isLibrary: Bool) async -> Playlist? {
        do {
            if isLibrary {
                var request = MusicLibraryRequest<Playlist>()
                request.filter(matching: \.id, equalTo: MusicItemID(id))
                return try await request.response().items.first
            }
            let request = MusicCatalogResourceRequest<Playlist>(matching: \.id, equalTo: MusicItemID(id))
            return try await request.response().items.first
        } catch {
            return nil
        }
    }

    /// Fetches songs for the given IDs from the catalog and library, returning
    /// them in the original order.
    private nonisolated static func fetchSongs(for ids: [String]) async -> [Song] {
        await ComposerResolver.fetchSongs(for: ids)
    }
}
