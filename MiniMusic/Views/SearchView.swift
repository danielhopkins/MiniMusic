import MusicKit
import SwiftUI

struct SearchView: View {
    @EnvironmentObject var searchVM: MusicSearchViewModel
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
        }
        .navigationTitle("Search")
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        TextField("Search Apple Music...", text: $searchVM.searchQuery)
            .textFieldStyle(.roundedBorder)
            .padding(12)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if searchVM.isLoading {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        } else if let error = searchVM.errorMessage {
            Spacer()
            Text(error)
                .foregroundStyle(.secondary)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        } else if searchVM.isEmpty {
            Spacer()
            if searchVM.searchQuery.isEmpty {
                Text("Search for songs, albums, artists, and playlists.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                Text("No results found.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Spacer()
        } else {
            resultsList
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !searchVM.songs.isEmpty {
                    sectionHeader("Songs")
                    ForEach(searchVM.songs) { song in
                        Button {
                            Task { await searchVM.playSong(song) }
                        } label: {
                            SearchRow(
                                title: song.title,
                                subtitle: song.artistName,
                                artwork: song.artwork
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !searchVM.albums.isEmpty {
                    sectionHeader("Albums")
                    ForEach(searchVM.albums) { album in
                        Button {
                            Task { await searchVM.playAlbum(album) }
                        } label: {
                            SearchRow(
                                title: album.title,
                                subtitle: album.artistName,
                                artwork: album.artwork
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !searchVM.artists.isEmpty {
                    sectionHeader("Artists")
                    ForEach(searchVM.artists) { artist in
                        Button {
                            Task { await searchVM.playTopSongForArtist(artist) }
                        } label: {
                            SearchRow(
                                title: artist.name,
                                subtitle: "Artist",
                                artwork: artist.artwork
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !searchVM.playlists.isEmpty {
                    sectionHeader("Playlists")
                    ForEach(searchVM.playlists) { playlist in
                        Button {
                            Task { await searchVM.playPlaylist(playlist) }
                        } label: {
                            SearchRow(
                                title: playlist.name,
                                subtitle: playlist.curatorName ?? "Apple Music",
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
}

// MARK: - Search Row

private struct SearchRow: View {
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
                .cornerRadius(4)
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
