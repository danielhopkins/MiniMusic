import SwiftUI
import MusicKit

struct PlayerView: View {
    @EnvironmentObject private var playerVM: PlayerViewModel
    @EnvironmentObject private var searchVM: MusicSearchViewModel
    @EnvironmentObject private var appState: AppState

    @State private var isSeeking = false
    @State private var seekTime: TimeInterval = 0

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack(path: $navigationPath) {
            mainContent
                .navigationDestination(for: NavigationDestination.self) { destination in
                    switch destination {
                    case .search:
                        SearchView()
                    case .queue:
                        QueueView()
                    case .library:
                        LibraryView()
                    case .player:
                        EmptyView()
                    }
                }
        }
        .frame(width: 320, height: 400)
    }

    @State private var navigationPath = NavigationPath()

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            nowPlayingSection
            Spacer(minLength: 4)
            controlsSection
            progressSection
            volumeSection
            Divider().padding(.top, 8)
            navigationSection
            Divider()
            bottomBar
        }
        .padding(.vertical, 8)
        .keyboardShortcut(.space, modifiers: [])
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search...", text: $searchVM.searchQuery)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit {
                    if !searchVM.searchQuery.isEmpty {
                        navigationPath.append(NavigationDestination.search)
                    }
                }
                .onChange(of: isSearchFocused) { _, focused in
                    if focused && !searchVM.searchQuery.isEmpty {
                        navigationPath.append(NavigationDestination.search)
                    }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Now Playing

    private var nowPlayingSection: some View {
        VStack(spacing: 6) {
            // Album artwork
            if let url = playerVM.artworkURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    artworkPlaceholder
                }
                .frame(width: 120, height: 120)
                .cornerRadius(8)
                .shadow(radius: 2)
            } else {
                artworkPlaceholder
            }

            // Track info
            VStack(spacing: 2) {
                Text(playerVM.currentTitle.isEmpty ? "Not Playing" : playerVM.currentTitle)
                    .font(.headline)
                    .lineLimit(1)

                if !playerVM.currentArtist.isEmpty || !playerVM.currentAlbumTitle.isEmpty {
                    Text(subtitleText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .frame(width: 120, height: 120)
            .overlay {
                Image(systemName: "music.note")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
    }

    private var subtitleText: String {
        switch (playerVM.currentArtist.isEmpty, playerVM.currentAlbumTitle.isEmpty) {
        case (false, false):
            return "\(playerVM.currentArtist) — \(playerVM.currentAlbumTitle)"
        case (false, true):
            return playerVM.currentArtist
        case (true, false):
            return playerVM.currentAlbumTitle
        case (true, true):
            return ""
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: 32) {
            Button { playerVM.skipBackward() } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            Button { playerVM.togglePlayPause() } label: {
                Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])

            Button { playerVM.skipForward() } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { isSeeking ? seekTime : playerVM.playbackTime },
                    set: { newValue in
                        isSeeking = true
                        seekTime = newValue
                    }
                ),
                in: 0...max(playerVM.duration, 1),
                onEditingChanged: { editing in
                    if !editing {
                        playerVM.seek(to: seekTime)
                        isSeeking = false
                    }
                }
            )

            HStack {
                Text(formatTime(isSeeking ? seekTime : playerVM.playbackTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Text(formatTime(playerVM.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Volume

    private var volumeSection: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            Slider(value: $playerVM.volume, in: 0...1)

            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Navigation

    private var navigationSection: some View {
        VStack(spacing: 0) {
            Button {
                navigationPath.append(NavigationDestination.queue)
            } label: {
                HStack {
                    Label("Queue", systemImage: "list.bullet")
                    Spacer()
                    Text(queueCountText)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            Button {
                navigationPath.append(NavigationDestination.library)
            } label: {
                HStack {
                    Label("Library", systemImage: "music.note.house")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
    }

    private var queueCountText: String {
        let entries = ApplicationMusicPlayer.shared.queue.entries
        let count = max(entries.count - 1, 0) // exclude current
        return count > 0 ? "\(count) up next" : ""
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button {} label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time >= 0 else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
