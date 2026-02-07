import SwiftUI
import MusicKit

struct PlayerView: View {
    @Environment(PlayerViewModel.self) private var playerVM
    @Environment(MusicSearchViewModel.self) private var searchVM
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    @State private var isSeeking = false
    @State private var seekTime: TimeInterval = 0

    @FocusState private var isSearchFocused: Bool
    @State private var navigationPath = NavigationPath()
    @State private var isHoveringArtwork = false

    var body: some View {
        @Bindable var searchVM = searchVM
        @Bindable var appState = appState

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
        .onChange(of: appState.isSearchFieldFocused) { _, shouldFocus in
            if shouldFocus {
                isSearchFocused = true
                appState.isSearchFieldFocused = false
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            nowPlayingSection
                .padding(.top, 4)
            progressSection
                .padding(.top, 6)
            Divider().padding(.top, 4)
            navigationSection
            Divider()
            bottomBar
        }
        .padding(.vertical, 8)
        .keyboardShortcut(.space, modifiers: [])
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        @Bindable var searchVM = searchVM

        return HStack {
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
        ZStack(alignment: .bottom) {
            // Album artwork - fills available width
            if let url = playerVM.artworkURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    artworkPlaceholder
                }
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .contentShape(Rectangle())
                .clipped()
            } else {
                artworkPlaceholder
            }

            // Gradient scrim + track info + controls overlay
            VStack(spacing: 6) {
                // Track info
                VStack(spacing: 2) {
                    Text(playerVM.currentTitle.isEmpty ? "Not Playing" : playerVM.currentTitle)
                        .font(.headline)
                        .lineLimit(1)

                    if !playerVM.currentArtist.isEmpty || !playerVM.currentAlbumTitle.isEmpty {
                        Text(subtitleText)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                // Playback controls
                controlsSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .padding(.top, 24)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .foregroundStyle(.white)
            .opacity(isHoveringArtwork ? 1 : 0)
        }
        .clipShape(.rect(cornerRadius: 8))
        .padding(.horizontal, 8)
        .onHover { hovering in
            isHoveringArtwork = hovering
        }
        .animation(.easeInOut(duration: 0.2), value: isHoveringArtwork)
    }

    private var artworkPlaceholder: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: 48))
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
            .accessibilityLabel("Previous track")

            Button { playerVM.togglePlayPause() } label: {
                Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(playerVM.isPlaying ? "Pause" : "Play")

            Button { playerVM.skipForward() } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
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
            .accessibilityLabel("Playback position")

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
        let count = playerVM.queueCount
        return count > 0 ? "\(count) up next" : ""
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button {
                appState.isMenuPresented = false
                openSettings()
                NSApp.activate()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")

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
