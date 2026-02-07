import MusicKit
import SwiftUI

struct SearchView: View {
    @EnvironmentObject var searchVM: MusicSearchViewModel
    @EnvironmentObject var appState: AppState

    @State private var selectedIndex: Int?
    @State private var keyMonitor: Any?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
        }
        .navigationTitle("Search")
        .onChange(of: searchVM.searchQuery) { _, _ in
            selectedIndex = nil
        }
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    // MARK: - Key Handling

    private func installKeyMonitor() {
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
                        Task { await searchVM.playItem(results[index]) }
                        searchVM.searchQuery = ""
                        searchVM.clearResults()
                        dismiss()
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
        let results = searchVM.allResults
        let sectionStarts = computeSectionStarts(results)

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        if let header = sectionStarts[index] {
                            sectionHeader(header)
                        }

                        Button {
                            Task { await searchVM.playItem(item) }
                        } label: {
                            SearchRow(
                                title: item.title,
                                subtitle: item.subtitle,
                                artwork: item.artwork,
                                isLibrary: item.isLibrary
                            )
                            .background(
                                selectedIndex == index
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear
                            )
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                if let newIndex {
                    withAnimation {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
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
}

// MARK: - Search Row

private struct SearchRow: View {
    let title: String
    let subtitle: String
    let artwork: Artwork?
    var isLibrary: Bool = false

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
