import Foundation
import MusicKit
import Combine
import Observation

@Observable final class PlayerViewModel {

    // MARK: - State

    private(set) var currentTitle: String = ""
    private(set) var currentArtist: String = ""
    private(set) var currentAlbumTitle: String = ""
    private(set) var artworkURL: URL?
    private(set) var isPlaying: Bool = false
    private(set) var playbackTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

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
            }
        }
    }

    func skipForward() {
        Task {
            try? await player.skipToNextEntry()
        }
    }

    func skipBackward() {
        Task {
            try? await player.skipToPreviousEntry()
        }
    }

    func seek(to time: TimeInterval) {
        player.playbackTime = time
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
        let queue = player.queue
        Task {
            try? await queue.insert(song, position: .tail)
        }
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
            artworkURL = nil
            duration = 0
            return
        }

        currentTitle = entry.title
        currentArtist = entry.subtitle ?? ""

        if let artwork = entry.artwork {
            artworkURL = artwork.url(width: 240, height: 240)
        } else {
            artworkURL = nil
        }

        // Fetch full song metadata for album title and duration
        if case let .song(song) = entry.item {
            currentAlbumTitle = song.albumTitle ?? ""
            duration = song.duration ?? 0
        } else {
            currentAlbumTitle = ""
            duration = 0
        }
    }

    private func startTimeObserver() {
        timeObserverTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.playbackTime = self.player.playbackTime
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}
