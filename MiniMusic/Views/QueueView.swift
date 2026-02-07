import MusicKit
import SwiftUI

struct QueueView: View {
    @Environment(AppState.self) var appState
    @Environment(PlayerViewModel.self) private var playerVM

    var body: some View {
        VStack(spacing: 0) {
            queueContent
        }
        .navigationTitle("Queue")
    }

    // MARK: - Queue Content

    @ViewBuilder
    private var queueContent: some View {
        let entries = playerVM.queueEntries
        let currentEntry = playerVM.currentQueueEntry

        if entries.isEmpty {
            Spacer()
            Text("Queue is empty.")
                .foregroundStyle(.secondary)
                .font(.caption)
            Spacer()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let current = currentEntry {
                        sectionHeader("Now Playing")
                        QueueRow(entry: current, isCurrent: true)
                    }

                    let upNext = upNextEntries(entries: entries, current: currentEntry)
                    if !upNext.isEmpty {
                        sectionHeader("Up Next")
                        ForEach(upNext) { entry in
                            QueueRow(entry: entry, isCurrent: false)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func upNextEntries(
        entries: [ApplicationMusicPlayer.Queue.Entry],
        current: ApplicationMusicPlayer.Queue.Entry?
    ) -> [ApplicationMusicPlayer.Queue.Entry] {
        guard let current else { return entries }
        if let idx = entries.firstIndex(where: { $0.id == current.id }), idx + 1 < entries.count {
            return Array(entries[(idx + 1)...])
        }
        return []
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

// MARK: - Queue Row

private struct QueueRow: View {
    let entry: ApplicationMusicPlayer.Queue.Entry
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let artwork = entry.artwork {
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
                Text(entry.title)
                    .font(.body)
                    .lineLimit(1)
                if let subtitle = entry.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isCurrent ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
    }
}
