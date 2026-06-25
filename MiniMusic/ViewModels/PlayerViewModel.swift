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

    // MARK: - Private

    nonisolated(unsafe) private let player = ApplicationMusicPlayer.shared
    private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var timeObserverTask: Task<Void, Never>?
    @ObservationIgnored private var metadataFetchTask: Task<Void, Never>?
    /// ID of the item the displayed metadata belongs to, so a late catalog
    /// fetch can be discarded if the track has already changed.
    @ObservationIgnored private var currentItemID: MusicItemID?

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
        Task {
            if isPlaying {
                player.pause()
            } else {
                try? await player.play()
                applyPendingResumeIfNeeded()
            }
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
        Task {
            player.queue = [song]
            try? await player.play()
        }
    }

    func play(_ songs: [Song]) {
        guard !songs.isEmpty else { return }
        Task {
            player.queue = ApplicationMusicPlayer.Queue(for: songs)
            try? await player.play()
        }
    }

    func play(_ album: Album) {
        Task {
            player.queue = [album]
            try? await player.play()
        }
    }

    func playPlaylist(_ playlist: Playlist) {
        Task {
            player.state.shuffleMode = .songs
            player.queue = [playlist]
            try? await player.prepareToPlay()
            try? await player.play()
        }
    }

    func play(_ station: Station) {
        Task {
            player.queue = [station]
            try? await player.play()
        }
    }

    func playTopSongForArtist(_ artist: Artist) {
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
        case .libraryAlbum(let album), .catalogAlbum(let album):
            play(album)
        case .libraryArtist(let artist), .catalogArtist(let artist):
            playTopSongForArtist(artist)
        case .libraryPlaylist(let playlist), .catalogPlaylist(let playlist):
            playPlaylist(playlist)
        }
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
        currentArtist = entry.subtitle ?? ""
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
                    self.playbackTime = self.player.playbackTime
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
            QueueSnapshot(songIDs: ids, currentIndex: currentIndex, playbackTime: time)
        )
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
    }

    /// Fetches songs for the given IDs from the catalog and library, returning
    /// them in the original order. Library IDs (prefixed `i.`) are resolved
    /// against the library; everything else against the catalog.
    private nonisolated static func fetchSongs(for ids: [String]) async -> [Song] {
        let libraryIDs = ids.filter { $0.hasPrefix("i.") }
        let catalogIDs = ids.filter { !$0.hasPrefix("i.") }

        var byID: [String: Song] = [:]

        for batch in catalogIDs.chunked(into: 25) {
            do {
                let request = MusicCatalogResourceRequest<Song>(
                    matching: \.id, memberOf: batch.map { MusicItemID($0) }
                )
                let response = try await request.response()
                for song in response.items { byID[song.id.rawValue] = song }
            } catch {
                // Skip this batch; other songs still restore.
            }
        }

        for batch in libraryIDs.chunked(into: 25) {
            do {
                var request = MusicLibraryRequest<Song>()
                request.filter(matching: \.id, memberOf: batch.map { MusicItemID($0) })
                let response = try await request.response()
                for song in response.items { byID[song.id.rawValue] = song }
            } catch {
                // Skip this batch; other songs still restore.
            }
        }

        return ids.compactMap { byID[$0] }
    }
}
