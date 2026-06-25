import Foundation

/// A serializable snapshot of the playback queue, persisted so the queue
/// survives app relaunches. We store song IDs (not the full `Song` objects,
/// which aren't serializable) plus the current position, and rehydrate the
/// songs from MusicKit on launch.
struct QueueSnapshot: Codable {
    /// Ordered catalog/library IDs of every song entry in the queue.
    var songIDs: [String]
    /// Index into `songIDs` of the entry that was playing.
    var currentIndex: Int
    /// Playback position within the current song, in seconds.
    var playbackTime: TimeInterval
}

/// UserDefaults-backed store for the queue snapshot.
enum QueuePersistence {
    private static let key = "MiniMusic.savedQueue"
    private static var defaults: UserDefaults { .standard }

    static func save(_ snapshot: QueueSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> QueueSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(QueueSnapshot.self, from: data)
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }
}

extension Array {
    /// Splits the array into chunks of at most `size` elements, for batching
    /// MusicKit requests (which cap the number of IDs per request).
    nonisolated func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
