import Foundation
import MusicKit
import Combine

@MainActor
final class PlayerViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var currentTitle: String = ""
    @Published private(set) var currentArtist: String = ""
    @Published private(set) var currentAlbumTitle: String = ""
    @Published private(set) var artworkURL: URL?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var playbackTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var volume: Float = 0.5

    // MARK: - Private

    private let player = ApplicationMusicPlayer.shared
    private var cancellables = Set<AnyCancellable>()
    private var timeObserverTask: Task<Void, Never>?

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

    func play(_ playlist: Playlist) {
        Task {
            player.queue = [playlist]
            try? await player.play()
        }
    }

    func play(_ station: Station) {
        Task {
            player.queue = [station]
            try? await player.play()
        }
    }

    func addToQueue(_ song: Song) {
        Task {
            try? await player.queue.insert(song, position: .tail)
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
                Task { @MainActor in
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
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }
        }
    }
}
