import MusicKit
import SwiftUI

struct QueueView: View {
    @Environment(AppState.self) var appState
    @Environment(PlayerViewModel.self) private var playerVM
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if playerVM.playbackSource != nil {
                sourceCard
                Divider()
            }
            queueContent
        }
        .frame(height: 450)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .automatic)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)

            Text("Queue")
                .font(.headline)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Playback Source

    @ViewBuilder
    private var sourceCard: some View {
        if let source = playerVM.playbackSource {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if let artwork = playerVM.sourceArtwork {
                        ArtworkImage(artwork, width: 44, height: 44)
                            .clipShape(.rect(cornerRadius: 5))
                    } else {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.quaternary)
                            .frame(width: 44, height: 44)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Playing from \(source.kindLabel)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(source.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(source.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }

                if source.supportsLibraryActions {
                    sourceActions
                }

                if let error = playerVM.sourceActionError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var sourceActions: some View {
        HStack(spacing: 8) {
            Button {
                Task { await playerVM.addSourceToLibrary() }
            } label: {
                Label(
                    playerVM.isSourceInLibrary ? "In Library" : "Add to Library",
                    systemImage: playerVM.isSourceInLibrary ? "checkmark" : "plus"
                )
            }
            .disabled(playerVM.isSourceInLibrary)

            Button {
                Task { await playerVM.favoriteSource() }
            } label: {
                Label(
                    playerVM.isSourceFavorited ? "Favorited" : "Favorite",
                    systemImage: playerVM.isSourceFavorited ? "heart.fill" : "heart"
                )
            }
            .disabled(playerVM.isSourceFavorited)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.caption)
    }

    // MARK: - Queue Content

    @ViewBuilder
    private var queueContent: some View {
        let entries = playerVM.queueEntries
        let currentEntry = playerVM.currentQueueEntry

        if entries.isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("Queue is empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
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
                ArtworkImage(artwork, width: 36, height: 36)
                    .clipShape(.rect(cornerRadius: 4))
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: 2) {
                let lines = ClassicalTitle.split(entry.title)
                Text(lines.work)
                    .font(.body)
                    .lineLimit(1)
                if let detail = lines.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let subtitle = entry.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
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
