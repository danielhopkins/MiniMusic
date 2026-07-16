import FoundationModels

/// Parses a natural-language music search query into a structured `SearchIntent`
/// using Apple's on-device Foundation Models. Every failure path — the model
/// being unavailable, a guardrail rejection, cancellation, or any other error —
/// returns `nil`, so callers fall back to the deterministic `SearchQueryParser`.
final class SearchIntentParser {

    /// Each parse builds a *fresh* session from these instructions. A single
    /// long-lived session would accumulate a transcript across every search and
    /// eventually overflow the context window, after which every `respond` throws
    /// and the app silently falls back to the deterministic parser until relaunch.
    /// Parses are independent, so per-request sessions are both correct and safe.
    private static let parseInstructions = """
            You turn a music search query — which may be misspelled or \
            conversational — into a structured Apple Music search. Fix clear \
            misspellings toward the real artist the user means ("tailor swift" → \
            "Taylor Swift"), but only when the corrected word is itself a real \
            musician; never turn a name into an unrelated non-music word.

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
              song, else empty. A classical catalogue or opus reference ("op 28 \
              no 24", "bwv 1041", "k 466") names one specific piece: put the \
              reference here formatted with periods ("Op. 28 No. 24"), keep the \
              composer in artist, and never discard the numbers.
            - categories: the kind of RESULT the user wants to see (songs, \
              albums, artists, playlists); empty if no type is named. Almost \
              never choose "artist": pick it ONLY when the user literally wants a \
              list of performers or bands (e.g. "bands like Radiohead", "find the \
              artist named X"). Simply mentioning an artist is NOT a request for \
              the "artist" category. When the user names an artist and asks for \
              their "songs", "tracks", "pieces", "works", or "music" — in any \
              phrasing — that means that artist's songs (categories [song]). If \
              they just name an artist with no result type, leave categories \
              empty.

            Popularity words ("popular", "top", "best", "greatest hits") are NOT \
            moods. "popular/top/best songs by an artist" means that artist's top \
            songs: set artist, categories [song], and leave descriptor empty — an \
            artist's top songs are already ranked by popularity.

            Examples: "tailor swift songs from the red album" → term "Taylor Swift \
            Red", artist "Taylor Swift", album "Red", categories [song]. \
            "classical playlists that are exciting" → term "classical", \
            descriptor "exciting", categories [playlist]. "songs from the matilda \
            netflix musical" → term "Matilda the Musical", album "Matilda the \
            Musical Netflix Soundtrack", categories [song]. "pieces by brahms" → \
            term "Brahms", artist "Brahms", categories [song]. "chopin op 28 no \
            24" → term "Chopin Op. 28 No. 24", artist "Chopin", song "Op. 28 \
            No. 24", categories [song]. "bach bwv 1041" → term "Bach BWV 1041", \
            artist "Bach", song "BWV 1041", categories [song]. "beethoven op \
            111" → term "Beethoven Op. 111", artist "Beethoven", song "Op. \
            111", categories [song].
            """

    /// A session warmed by `prewarm()`, consumed by the next `parse` so the first
    /// keystroke-driven search isn't cold. Each parse then warms a replacement.
    private var warmSession: LanguageModelSession?

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: Self.parseInstructions)
    }

    /// Whether the on-device model is ready to use on this device right now.
    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Warms a fresh session during idle time (e.g. when the search view appears)
    /// to cut first-response latency. No-op when the model is unavailable.
    func prewarm() {
        guard isAvailable, warmSession == nil else { return }
        let session = makeSession()
        session.prewarm()
        warmSession = session
    }

    /// Returns the model's parsed intent, or `nil` if the model is unavailable
    /// or the request fails. Cancellation (e.g. a newer keystroke) surfaces as
    /// `nil` too, letting the caller stop cleanly. Uses a fresh session per call
    /// so no transcript carries over between searches and overflows the context.
    func parse(_ query: String) async -> SearchIntent? {
        guard isAvailable else { return nil }
        let session = warmSession ?? makeSession()
        warmSession = nil
        do {
            let intent = try await session.respond(to: query, generating: SearchIntent.self).content
            // Warm a replacement for the next search while we're idle.
            prewarm()
            return intent
        } catch {
            return nil
        }
    }

    // MARK: - Vibe re-ranking

    /// Fresh per re-rank call for the same reason as `parseInstructions`: a
    /// shared session would accumulate a transcript and eventually overflow.
    private static let rankInstructions = """
            You re-rank music search results to match a requested mood or vibe. \
            Given the vibe and a numbered list of results (by name), return the \
            indices to keep — best match first — and drop any whose name clearly \
            contradicts the vibe (e.g. a "calm" result when the user wants \
            "exciting"). When a name gives no signal either way, keep it rather \
            than guess. Never invent indices outside the list.
            """

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
            let session = LanguageModelSession(instructions: Self.rankInstructions)
            let selection = try await session.respond(
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
