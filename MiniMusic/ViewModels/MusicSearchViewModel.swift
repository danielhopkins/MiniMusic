import Combine
import MusicKit
import SwiftUI

@MainActor
final class MusicSearchViewModel: ObservableObject {

    // MARK: - Published State

    @Published var searchQuery = ""
    @Published private(set) var songs: MusicItemCollection<Song> = []
    @Published private(set) var albums: MusicItemCollection<Album> = []
    @Published private(set) var artists: MusicItemCollection<Artist> = []
    @Published private(set) var playlists: MusicItemCollection<Playlist> = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    var isEmpty: Bool {
        songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.performSearch(query: query)
            }
            .store(in: &cancellables)
    }

    // MARK: - Search

    private func performSearch(query: String) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearResults()
            return
        }

        searchTask = Task {
            isLoading = true
            errorMessage = nil

            do {
                var request = MusicCatalogSearchRequest(term: trimmed, types: [
                    Song.self,
                    Album.self,
                    Artist.self,
                    Playlist.self,
                ])
                request.limit = 10

                let response = try await request.response()

                guard !Task.isCancelled else { return }

                songs = response.songs
                albums = response.albums
                artists = response.artists
                playlists = response.playlists
            } catch is CancellationError {
                // Ignored — search was superseded by a newer query.
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }

            if !Task.isCancelled {
                isLoading = false
            }
        }
    }

    func clearResults() {
        songs = []
        albums = []
        artists = []
        playlists = []
        isLoading = false
        errorMessage = nil
    }

    // MARK: - Playback

    private let player = ApplicationMusicPlayer.shared

    func playSong(_ song: Song) async {
        do {
            player.queue = [song]
            try await player.play()
        } catch {
            errorMessage = "Failed to play song: \(error.localizedDescription)"
        }
    }

    func playAlbum(_ album: Album) async {
        do {
            player.queue = [album]
            try await player.play()
        } catch {
            errorMessage = "Failed to play album: \(error.localizedDescription)"
        }
    }

    func playPlaylist(_ playlist: Playlist) async {
        do {
            player.state.shuffleMode = .songs
            player.queue = [playlist]
            try await player.prepareToPlay()
            try await player.play()
        } catch {
            errorMessage = "Failed to play playlist: \(error.localizedDescription)"
        }
    }

    func playTopSongForArtist(_ artist: Artist) async {
        do {
            let detailedArtist = try await artist.with([.topSongs])
            guard let topSong = detailedArtist.topSongs?.first else {
                errorMessage = "No songs found for this artist."
                return
            }
            player.queue = [topSong]
            try await player.play()
        } catch {
            errorMessage = "Failed to play artist: \(error.localizedDescription)"
        }
    }
}
