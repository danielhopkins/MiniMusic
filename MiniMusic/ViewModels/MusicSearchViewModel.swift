import MusicKit
import SwiftUI
import Observation

@MainActor
@Observable final class MusicSearchViewModel {

    // MARK: - State

    var searchQuery = "" {
        didSet { debounceSearch() }
    }
    private(set) var songs: MusicItemCollection<Song> = []
    private(set) var albums: MusicItemCollection<Album> = []
    private(set) var artists: MusicItemCollection<Artist> = []
    private(set) var playlists: MusicItemCollection<Playlist> = []
    private(set) var librarySongs: MusicItemCollection<Song> = []
    private(set) var libraryAlbums: MusicItemCollection<Album> = []
    private(set) var libraryArtists: MusicItemCollection<Artist> = []
    private(set) var libraryPlaylists: MusicItemCollection<Playlist> = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

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

    private var searchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    // MARK: - Debounce

    private func debounceSearch() {
        debounceTask?.cancel()
        let query = searchQuery
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            performSearch(query: query)
        }
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
}
