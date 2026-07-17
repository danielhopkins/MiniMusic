import MusicKit

/// Resolves composer names for songs by ID, in bulk.
///
/// MusicKit doesn't hydrate `composerName` on the lightweight `Song` values that
/// come back from catalog/library searches or sit in the playback queue, so the
/// composer has to be fetched by ID. Doing that one row at a time is slow; this
/// batches the lookups (25 IDs per request) and routes catalog vs. library IDs
/// to the right API.
enum ComposerResolver {
    /// Fetches songs for the given IDs from the catalog and library, returning
    /// them in the original order. Library IDs (prefixed `i.`) are resolved
    /// against the library; everything else against the catalog.
    nonisolated static func fetchSongs(for ids: [String]) async -> [Song] {
        let libraryIDs = ids.filter { $0.hasPrefix("i.") }
        let catalogIDs = ids.filter { !$0.hasPrefix("i.") }

        var byID: [String: Song] = [:]

        for batch in catalogIDs.chunked(into: 25) {
            do {
                let request = MusicCatalogResourceRequest<Song>(
                    matching: \.id, memberOf: batch.map { MusicItemID($0) }
                )
                let response = try await request.response()
                for song in response.items { byID[song.id.rawValue] = song }
            } catch {
                // Skip this batch; other songs still resolve.
            }
        }

        for batch in libraryIDs.chunked(into: 25) {
            do {
                var request = MusicLibraryRequest<Song>()
                request.filter(matching: \.id, memberOf: batch.map { MusicItemID($0) })
                let response = try await request.response()
                for song in response.items { byID[song.id.rawValue] = song }
            } catch {
                // Skip this batch; other songs still resolve.
            }
        }

        return ids.compactMap { byID[$0] }
    }
}
