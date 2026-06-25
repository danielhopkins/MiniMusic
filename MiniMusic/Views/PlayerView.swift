import Combine
import MusicKit
import SwiftUI

struct PlayerView: View {
    @Environment(PlayerViewModel.self) private var playerVM
    @Environment(MusicSearchViewModel.self) private var searchVM
    @Environment(AppState.self) private var appState

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
        // Width is fixed; height follows the content so there's no dead space
        // above/below the player. The scrollable Queue/Library destinations set
        // their own height.
        .frame(width: 320)
        .onChange(of: appState.isSearchFieldFocused) { _, shouldFocus in
            if shouldFocus {
                isSearchFocused = true
                appState.isSearchFieldFocused = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuBarDismissed)) { _ in
            navigationPath = NavigationPath()
        }
        .task {
            // Restore the saved queue if authorization was only just granted
            // (the launch-time attempt is a no-op until authorized).
            await playerVM.restoreQueueIfNeeded()
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            nowPlayingSection
                .padding(.top, 4)
            trackInfoRow
                .padding(.top, 8)
            progressSection
                .padding(.top, 6)
            Divider().padding(.top, 4)
            navigationSection
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
            Button {
                NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Now Playing

    private var nowPlayingSection: some View {
        ZStack(alignment: .bottom) {
            // Album artwork - fills available width, cropped to a fixed height.
            // `ArtworkImage` is a fixed-size view, so anchor the layout to a sized
            // container and clip the artwork into it (a plain `.frame(height:)`
            // doesn't constrain it and lets the panel grow).
            if let artwork = playerVM.artwork {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .overlay {
                        ArtworkImage(artwork, width: 320, height: 320)
                    }
                    .contentShape(Rectangle())
                    .clipped()
            } else {
                artworkPlaceholder
            }

            // Gradient scrim + playback controls overlay (revealed on hover).
            // Track text now lives in the always-visible `trackInfoRow` below.
            controlsSection
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .padding(.top, 36)
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
            .frame(height: 190)
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

    // MARK: - Track Info Row (always visible)

    private var trackInfoRow: some View {
        Group {
            if playerVM.currentTitle.isEmpty {
                Text("Not Playing")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else if playerVM.isClassical {
                classicalInfo
            } else {
                standardInfo
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private var standardInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(playerVM.currentTitle)
                .font(.headline)
                .lineLimit(1)

            if !subtitleText.isEmpty {
                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// Classical works get a dedicated layout: the work name on its own line,
    /// then the catalogue/movement detail, then a composer · performer line so
    /// the people who matter for a recording are always visible.
    private var classicalInfo: some View {
        let lines = classicalTitleLines

        return VStack(alignment: .leading, spacing: 3) {
            Text(lines.work)
                .font(.headline)
                .lineLimit(2)

            if let detail = lines.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !composerPerformerText.isEmpty {
                Text(composerPerformerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// The two title lines for the classical layout: the work name, and an
    /// optional catalogue/movement detail.
    ///
    /// Apple Music formats classical titles consistently as
    /// `Work, Catalogue: Movement`, so we split the full track title rather than
    /// relying on the `workName`/`movementName` fields, which are inconsistently
    /// populated (and often re-embed the catalogue number, breaking the layout).
    private var classicalTitleLines: (work: String, detail: String?) {
        ClassicalTitle.split(playerVM.currentTitle)
    }

    /// "Composer · Performers", omitting either side when unavailable.
    private var composerPerformerText: String {
        [playerVM.currentComposer, playerVM.currentArtist]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
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

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite && time >= 0 else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
