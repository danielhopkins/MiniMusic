import MusicKit
import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) var appState
    @Environment(PlayerViewModel.self) private var playerVM

    @State private var playlists: MusicItemCollection<Playlist> = []
    @State private var recentAlbums: MusicItemCollection<Album> = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .navigationTitle("Library")
        .task {
            await loadLibrary()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading {
            Spacer()
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            Spacer()
        } else if let error = errorMessage {
            Spacer()
            Text(error)
                .foregroundStyle(.secondary)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity)
            Spacer()
        } else if playlists.isEmpty && recentAlbums.isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "music.note.house")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("Your library is empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            Spacer()
        } else {
            libraryList
        }
    }

    // MARK: - Library List

    private var libraryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !recentAlbums.isEmpty {
                    sectionHeader("Recently Played")
                    ForEach(recentAlbums) { album in
                        Button {
                            playAlbum(album)
                        } label: {
                            LibraryRow(
                                title: album.title,
                                subtitle: album.artistName,
                                artwork: album.artwork
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !playlists.isEmpty {
                    sectionHeader("Playlists")
                    ForEach(playlists) { playlist in
                        Button {
                            playPlaylist(playlist)
                        } label: {
                            LibraryRow(
                                title: playlist.name,
                                subtitle: playlist.curatorName ?? "Playlist",
                                artwork: playlist.artwork
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    // MARK: - Data Loading

    private func loadLibrary() async {
        isLoading = true
        errorMessage = nil

        do {
            var playlistRequest = MusicLibraryRequest<Playlist>()
            playlistRequest.limit = 25
            let playlistResponse = try await playlistRequest.response()
            playlists = playlistResponse.items

            let recentRequest = MusicRecentlyPlayedRequest<RecentlyPlayedMusicItem>()
            _ = try await recentRequest.response()
            recentAlbums = []
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Playback

    private func playPlaylist(_ playlist: Playlist) {
        playerVM.playPlaylist(playlist)
    }

    private func playAlbum(_ album: Album) {
        playerVM.play(album)
    }
}

// MARK: - Library Row

private struct LibraryRow: View {
    let title: String
    let subtitle: String
    let artwork: Artwork?

    var body: some View {
        HStack(spacing: 10) {
            if let artwork {
                AsyncImage(url: artwork.url(width: 40, height: 40)) { image in
                    image.resizable()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                }
                .frame(width: 36, height: 36)
                .clipShape(.rect(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
