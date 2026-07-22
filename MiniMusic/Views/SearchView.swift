import MusicKit
import SwiftUI

struct SearchView: View {
    @Environment(MusicSearchViewModel.self) var searchVM
    @Environment(AppState.self) var appState
    @Environment(PlayerViewModel.self) private var playerVM

    @State private var selectedIndex: Int?
    @State private var keyMonitor: Any?
    @State private var favoritedIDs: Set<String> = []
    @State private var addedToLibraryIDs: Set<String> = []
    @FocusState private var isSearchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var searchVM = searchVM

        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            Divider()
            content
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .automatic)
        .onChange(of: searchVM.searchQuery) { _, _ in
            selectedIndex = nil
        }
        .onAppear {
            installKeyMonitor()
            searchVM.prewarm()
        }
        .task { isSearchFocused = true }
        .onDisappear { removeKeyMonitor() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)

            Text("Search")
                .font(.headline)

            Spacer()

            if searchVM.usedIntelligence {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tint)
                    .help("Results refined by Apple Intelligence")
                    .transition(.opacity.combined(with: .scale))
                    .accessibilityLabel("Refined by Apple Intelligence")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: searchVM.usedIntelligence)
    }

    // MARK: - Playing a Result

    /// Starts a result and returns to the player. Both ways of choosing a result
    /// — clicking a row and pressing Return on the selection — go through here,
    /// so they can't drift apart on what "choosing" entails.
    private func play(_ item: SearchResultItem) {
        playerVM.playItem(item)
        searchVM.searchQuery = ""
        searchVM.clearResults()
        dismiss()
    }

    // MARK: - Key Handling

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 125: // down arrow
                moveSelection(by: 1)
                return nil
            case 126: // up arrow
                moveSelection(by: -1)
                return nil
            case 36: // return
                if let index = selectedIndex {
                    let results = searchVM.allResults
                    if index >= 0 && index < results.count {
                        play(results[index])
                        return nil
                    }
                }
                return event
            case 53: // escape
                if selectedIndex != nil {
                    selectedIndex = nil
                    return nil
                }
                dismiss()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        @Bindable var searchVM = searchVM

        return TextField("Search Apple Music...", text: $searchVM.searchQuery)
            .textFieldStyle(.roundedBorder)
            .focused($isSearchFocused)
            .padding(12)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let error = searchVM.errorMessage {
            Spacer()
            Text(error)
                .foregroundStyle(.secondary)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding()
            Spacer()
        } else if !searchVM.isEmpty {
            resultsList
        } else if searchVM.isLoading {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        } else if searchVM.searchQuery.isEmpty {
            Spacer()
            Text("Search for songs, albums, artists, and playlists.\nTry \u{201C}piano playlist\u{201D} or \u{201C}swift artist\u{201D} to filter.")
                .foregroundStyle(.secondary)
                .font(.caption)
                .multilineTextAlignment(.center)
            Spacer()
        } else {
            Spacer()
            Text("No results found.")
                .foregroundStyle(.secondary)
                .font(.caption)
            Spacer()
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        let results = searchVM.allResults
        let sectionStarts = computeSectionStarts(results)

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        if let header = sectionStarts[index] {
                            sectionHeader(header)
                        }

                        HStack(spacing: 0) {
                            SearchRow(
                                title: item.title,
                                subtitle: item.subtitle,
                                composer: searchVM.composer(for: item),
                                artwork: item.artwork,
                                isLibrary: item.isLibrary
                            )
                            .onTapGesture { play(item) }

                            actionButtons(for: item)
                        }
                        .background(
                            selectedIndex == index
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                        .clipShape(.rect(cornerRadius: 4))
                        .contextMenu { contextMenuItems(for: item) }
                        .id(index)
                        .accessibilityLabel("\(item.title), \(item.subtitle)")
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: Self.maxResultsHeight)
            .onChange(of: selectedIndex) { _, newIndex in
                if let newIndex {
                    withAnimation {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }

    /// Caps the results list so a long result set scrolls inside the panel
    /// instead of growing the window past the screen. Leaves headroom for the
    /// header, search bar, and menu bar; falls back to a safe constant when the
    /// screen height is unavailable.
    private static var maxResultsHeight: CGFloat {
        let available = NSScreen.main?.visibleFrame.height ?? 800
        return max(240, min(520, available - 220))
    }

    private func computeSectionStarts(_ results: [SearchResultItem]) -> [Int: String] {
        var starts: [Int: String] = [:]
        var lastSection = ""
        for (index, item) in results.enumerated() {
            if item.sectionName != lastSection {
                lastSection = item.sectionName
                starts[index] = lastSection
            }
        }
        return starts
    }

    // MARK: - Helpers

    private func moveSelection(by offset: Int) {
        let count = searchVM.allResults.count
        guard count > 0 else { return }

        if let current = selectedIndex {
            let next = current + offset
            if next >= 0 && next < count {
                selectedIndex = next
            }
        } else {
            selectedIndex = offset > 0 ? 0 : count - 1
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

    // MARK: - Context Menu

    @ViewBuilder
    private func actionButtons(for item: SearchResultItem) -> some View {
        if item.supportsLibraryActions {
            HStack(spacing: 2) {
                if item.isLibrary || addedToLibraryIDs.contains(item.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .frame(width: 24, height: 24)
                } else {
                    Button { addToLibrary(item) } label: {
                        Image(systemName: "plus.circle")
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                }
                Button { favoriteItem(item) } label: {
                    Image(systemName: favoritedIDs.contains(item.id) ? "star.fill" : "star")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .buttonStyle(.borderless)
            .padding(.trailing, 8)
        }
    }

    @ViewBuilder
    private func contextMenuItems(for item: SearchResultItem) -> some View {
        if !item.isLibrary && item.supportsLibraryActions {
            if addedToLibraryIDs.contains(item.id) {
                Button("Added to Library", systemImage: "checkmark.circle.fill") {}
                    .disabled(true)
            } else {
                Button("Add to Library", systemImage: "plus") {
                    addToLibrary(item)
                }
            }
        }
        if item.supportsLibraryActions {
            Button(
                favoritedIDs.contains(item.id) ? "Favorited" : "Favorite",
                systemImage: favoritedIDs.contains(item.id) ? "star.fill" : "star"
            ) {
                favoriteItem(item)
            }
        }
    }

    private func addToLibrary(_ item: SearchResultItem) {
        Task {
            do {
                let (type, id) = try libraryAddResource(for: item)
                let url = URL(string: "https://api.music.apple.com/v1/me/library?ids[\(type)]=\(id.rawValue)")!
                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = "POST"
                let request = MusicDataRequest(urlRequest: urlRequest)
                let _ = try await request.response()
                addedToLibraryIDs.insert(item.id)
            } catch {
                print("Failed to add to library: \(error)")
            }
        }
    }

    private func libraryAddResource(for item: SearchResultItem) throws -> (String, MusicItemID) {
        switch item {
        case .catalogSong(let s): return ("songs", s.id)
        case .catalogAlbum(let a): return ("albums", a.id)
        case .catalogPlaylist(let p): return ("playlists", p.id)
        default: throw CancellationError()
        }
    }

    private func favoriteItem(_ item: SearchResultItem) {
        Task {
            do {
                let (resourceType, itemId) = try ratingResource(for: item)
                let url = URL(string: "https://api.music.apple.com/v1/me/ratings/\(resourceType)/\(itemId.rawValue)")!
                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = "PUT"
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                    "type": "rating",
                    "attributes": ["value": 1],
                ])
                let request = MusicDataRequest(urlRequest: urlRequest)
                let _ = try await request.response()
                favoritedIDs.insert(item.id)
            } catch {
                print("Failed to favorite: \(error)")
            }
        }
    }

    private func ratingResource(for item: SearchResultItem) throws -> (String, MusicItemID) {
        switch item {
        case .catalogSong(let s): return ("songs", s.id)
        case .librarySong(let s): return ("library-songs", s.id)
        case .catalogAlbum(let a): return ("albums", a.id)
        case .libraryAlbum(let a): return ("library-albums", a.id)
        case .catalogPlaylist(let p): return ("playlists", p.id)
        case .libraryPlaylist(let p): return ("library-playlists", p.id)
        case .catalogArtist, .libraryArtist, .catalogStation:
            throw CancellationError()
        }
    }
}

// MARK: - Search Row

private struct SearchRow: View {
    let title: String
    let subtitle: String
    var composer: String? = nil
    let artwork: Artwork?
    var isLibrary: Bool = false

    /// "Composer · Performer" once a classical composer resolves, otherwise just
    /// the performer — matching the queue and now-playing views. Given names are
    /// abbreviated to initials to save horizontal space.
    private var credit: String {
        let abbreviated = composer.map(ComposerName.abbreviated) ?? ""
        return [abbreviated, subtitle].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            if let artwork {
                ArtworkImage(artwork, width: 36, height: 36)
                    .clipShape(.rect(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: 2) {
                // Same split the player and queue use: the catalogue and movement
                // move to their own line instead of being truncated away, which is
                // what tells "Op. 28: No. 24" apart from its 23 siblings. Ordinary
                // titles carry no detail and stay two lines.
                let lines = ClassicalTitle.split(title)
                Text(lines.work)
                    .font(.body)
                    .lineLimit(2)
                if let detail = lines.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(credit)
                    .font(.caption)
                    .foregroundStyle(lines.detail == nil ? .secondary : .tertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
