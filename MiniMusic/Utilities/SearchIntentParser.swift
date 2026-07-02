import FoundationModels

/// Parses a natural-language music search query into a structured `SearchIntent`
/// using Apple's on-device Foundation Models. Every failure path — the model
/// being unavailable, a guardrail rejection, cancellation, or any other error —
/// returns `nil`, so callers fall back to the deterministic `SearchQueryParser`.
final class SearchIntentParser {

    private lazy var session = LanguageModelSession(
        instructions: """
            You turn a music search query — which may be misspelled or \
            conversational — into a structured Apple Music search. Fix obvious \
            misspellings throughout ("tailor swift" → "Taylor Swift").

            Fill these fields:
            - term: a clean search string for the core SUBJECT only (genre, \
              artist, album, song), WITHOUT mood/vibe adjectives, with filler like \
              "from", "the", "by" removed. E.g. "exciting classical playlists" → \
              "classical"; "tailor swift songs from the red album" → "Taylor \
              Swift Red".
            - descriptor: mood/vibe/energy words like "exciting", "relaxing", \
              "upbeat", "sad"; empty if none.
            - artist: the artist/band name if one is named, else empty.
            - album: the album name if a specific album is named, OR the \
              soundtrack/cast album of a named movie, show, or musical (keep \
              distinguishing words like the platform or year); else empty.
            - song: a specific song title if the user asked for one particular \
              song, else empty.
            - categories: the kinds of results asked for (songs, albums, artists, \
              playlists); empty if no type is named.

            Examples: "tailor swift songs from the red album" → term "Taylor Swift \
            Red", artist "Taylor Swift", album "Red", categories [song]. \
            "classical playlists that are exciting" → term "classical", \
            descriptor "exciting", categories [playlist]. "songs from the matilda \
            netflix musical" → term "Matilda the Musical", album "Matilda the \
            Musical Netflix Soundtrack", categories [song].
            """
    )

    /// Whether the on-device model is ready to use on this device right now.
    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Warms the model during idle time (e.g. when the search view appears) to
    /// cut first-response latency. No-op when the model is unavailable.
    func prewarm() {
        guard isAvailable else { return }
        session.prewarm()
    }

    /// Returns the model's parsed intent, or `nil` if the model is unavailable
    /// or the request fails. Cancellation (e.g. a newer keystroke) surfaces as
    /// `nil` too, letting the caller stop cleanly.
    func parse(_ query: String) async -> SearchIntent? {
        guard isAvailable else { return nil }
        do {
            return try await session.respond(to: query, generating: SearchIntent.self).content
        } catch {
            return nil
        }
    }

    // MARK: - Vibe re-ranking

    private lazy var rankingSession = LanguageModelSession(
        instructions: """
            You re-rank music search results to match a requested mood or vibe. \
            Given the vibe and a numbered list of results (by name), return the \
            indices to keep — best match first — and drop any whose name clearly \
            contradicts the vibe (e.g. a "calm" result when the user wants \
            "exciting"). When a name gives no signal either way, keep it rather \
            than guess. Never invent indices outside the list.
            """
    )

    /// Given candidate result names, returns the indices to keep (best first),
    /// filtered and reordered to match `vibe`. Returns `nil` to signal "leave the
    /// results as they are" — on unavailability, failure, or an unusable answer.
    func rerank(candidates: [String], vibe: String, query: String) async -> [Int]? {
        guard isAvailable, !candidates.isEmpty else { return nil }

        let list = candidates.enumerated()
            .map { "\($0.offset): \($0.element)" }
            .joined(separator: "\n")
        let prompt = """
            The user searched for "\(query)" wanting a "\(vibe)" vibe. Keep the \
            results that fit and drop those that clearly don't.

            \(list)
            """

        do {
            let selection = try await rankingSession.respond(
                to: prompt, generating: RankedSelection.self
            ).content

            // Keep only valid, de-duplicated indices, preserving the model's order.
            var seen = Set<Int>()
            let ordered = selection.keptIndices.filter { index in
                guard index >= 0, index < candidates.count, !seen.contains(index) else { return false }
                seen.insert(index)
                return true
            }
            return ordered.isEmpty ? nil : ordered
        } catch {
            return nil
        }
    }
}

/// The subset of candidate indices the vibe re-ranker chose to keep.
@Generable
struct RankedSelection {
    @Guide(description: "Indices of the results to keep, best match for the vibe first, dropping any that clearly contradict it.")
    var keptIndices: [Int]
}
