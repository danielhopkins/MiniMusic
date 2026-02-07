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
    @Published private(set) var librarySongs: MusicItemCollection<Song> = []
    @Published private(set) var libraryAlbums: MusicItemCollection<Album> = []
    @Published private(set) var libraryArtists: MusicItemCollection<Artist> = []
    @Published private(set) var libraryPlaylists: MusicItemCollection<Playlist> = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    var isEmpty: Bool {
        songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty
            && librarySongs.isEmpty && libraryAlbums.isEmpty && libraryArtists.isEmpty
            && libraryPlaylists.isEmpty
    }

    var allResults: [SearchResultItem] {
        var items: [SearchResultItem] = []
        items += librarySongs.map { .librarySong($0) }
        items += libraryAlbums.map { .libraryAlbum($0) }
        items += libraryArtists.map { .libraryArtist($0) }
        items += libraryPlaylists.map { .libraryPlaylist($0) }
        items += songs.map { .catalogSong($0) }
        items += albums.map { .catalogAlbum($0) }
        items += artists.map { .catalogArtist($0) }
        items += playlists.map { .catalogPlaylist($0) }
        return items
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

            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.performLibrarySearch(term: trimmed) }
                group.addTask { await self.performCatalogSearch(term: trimmed) }
            }

            if !Task.isCancelled {
                isLoading = false
            }
        }
    }

    private func performLibrarySearch(term: String) async {
        do {
            var songRequest = MusicLibrarySearchRequest(term: term, types: [Song.self])
            songRequest.limit = 5
            let songResponse = try await songRequest.response()

            var albumRequest = MusicLibrarySearchRequest(term: term, types: [Album.self])
            albumRequest.limit = 5
            let albumResponse = try await albumRequest.response()

            var artistRequest = MusicLibrarySearchRequest(term: term, types: [Artist.self])
            artistRequest.limit = 5
            let artistResponse = try await artistRequest.response()

            var playlistRequest = MusicLibrarySearchRequest(term: term, types: [Playlist.self])
            playlistRequest.limit = 5
            let playlistResponse = try await playlistRequest.response()

            guard !Task.isCancelled else { return }

            librarySongs = songResponse.songs
            libraryAlbums = albumResponse.albums
            libraryArtists = artistResponse.artists
            libraryPlaylists = playlistResponse.playlists
        } catch is CancellationError {
            // Ignored
        } catch {
            guard !Task.isCancelled else { return }
            // Library search errors are non-fatal; catalog results still show
        }
    }

    private func performCatalogSearch(term: String) async {
        do {
            var request = MusicCatalogSearchRequest(term: term, types: [
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
    }

    func clearResults() {
        songs = []
        albums = []
        artists = []
        playlists = []
        librarySongs = []
        libraryAlbums = []
        libraryArtists = []
        libraryPlaylists = []
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

    func playItem(_ item: SearchResultItem) async {
        switch item {
        case .librarySong(let song), .catalogSong(let song):
            await playSong(song)
        case .libraryAlbum(let album), .catalogAlbum(let album):
            await playAlbum(album)
        case .libraryArtist(let artist), .catalogArtist(let artist):
            await playTopSongForArtist(artist)
        case .libraryPlaylist(let playlist), .catalogPlaylist(let playlist):
            await playPlaylist(playlist)
        }
    }
}
