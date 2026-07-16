#if DEBUG
import Foundation
import MusicKit

/// Debug-only harness that runs a real search and prints what came back.
///
/// `Tools/IntentBench` can exercise the parser and planner from a plain binary,
/// but MusicKit can't be reached that way: an Apple Music grant is tied to a
/// bundle identifier, so a bare CLI aborts in TCC no matter how it's signed.
/// Running inside the signed, already-authorized app is what makes the fetch and
/// ranking observable — the part `inspect.sh` is blind to.
///
/// It drives `MusicSearchViewModel` exactly as typing does, so what it prints is
/// the production path, not a reimplementation of it.
///
///   MINIMUSIC_PROBE="chopin op 28 no 24" \
///     ~/Library/Developer/Xcode/DerivedData/MiniMusic-*/Build/Products/Debug/MiniMusic.app/Contents/MacOS/MiniMusic
enum CatalogueProbe {

    /// The query to probe, or nil for a normal launch.
    static var requestedQuery: String? {
        ProcessInfo.processInfo.environment["MINIMUSIC_PROBE"]
    }

    /// Runs `query` through `viewModel` and prints each result with the
    /// catalogue tier it scored, then exits. Tier 2 is the piece asked for,
    /// 1 a sibling in the same opus, 0 unrelated — so a correct search shows
    /// tier 2 at the top.
    static func run(query: String, viewModel: MusicSearchViewModel) async {
        let reference = CatalogueReference.extract(from: query) ?? ""
        print("── probe: \"\(query)\"")
        print("   reference: \"\(reference)\"")

        viewModel.searchQuery = query

        // The view model debounces at 500ms, then fetches; wait for it to settle
        // rather than racing it.
        try? await Task.sleep(for: .milliseconds(900))
        for _ in 0..<100 where viewModel.isLoading {
            try? await Task.sleep(for: .milliseconds(100))
        }

        let results = viewModel.allResults
        print("   results: \(results.count)  (intelligence: \(viewModel.usedIntelligence))")
        guard !results.isEmpty else {
            print("   ⚠️ no results")
            exit(1)
        }

        func isMatch(_ item: SearchResultItem) -> Bool {
            !reference.isEmpty && CatalogueReference.isMovement(title: item.title, of: reference)
        }

        for (index, item) in results.enumerated() {
            let tier = reference.isEmpty
                ? 0
                : CatalogueReference.matchTier(title: item.title, reference: reference)
            print(String(format: "   %2d. [tier %d] %@ — %@ %@",
                         index + 1, tier, item.title, item.subtitle,
                         isMatch(item) ? "◀ MATCH" : ""))
        }

        let matches = results.filter(isMatch)
        print("   matches: \(matches.count)  first at: \(results.firstIndex(where: isMatch).map { $0 + 1 } ?? -1)")

        if !reference.isEmpty {
            let artist = query.replacingOccurrences(of: reference, with: "")
                .trimmingCharacters(in: .whitespaces)
            await probeWorkResolution(reference: reference, artist: artist)
        }
        exit(matches.isEmpty ? 1 : 0)
    }

    /// Traces `MusicSearchViewModel.surfaceCatalogueWork` step by step: which
    /// albums the work search returns, which one gets picked, and what its tracks
    /// score. This is the fallback that's supposed to guarantee the referenced
    /// piece appears when Apple's lexical search omits it.
    private static func probeWorkResolution(reference: String, artist: String) async {
        let work = CatalogueReference.workLevel(reference)
        let searchTerm = artist.isEmpty ? reference : "\(artist) \(work)"
        print("── work resolution: term=\"\(searchTerm)\"  work=\"\(work)\"")
        do {
            var request = MusicCatalogSearchRequest(term: searchTerm, types: [Album.self])
            request.limit = 10
            let response = try await request.response()
            print("   albums: \(response.albums.count)")
            for album in response.albums {
                let tier = CatalogueReference.matchTier(title: album.title, reference: work)
                print("     [tier \(tier)] \(album.title) — \(album.artistName)")
            }

            let candidates = CatalogueReference.ranked(
                Array(response.albums), reference: work, title: \.title)
            guard let album = candidates.first,
                  CatalogueReference.matchTier(title: album.title, reference: work) > 0
            else {
                print("   ⚠️ no album title carries \"\(work)\" → surfaceCatalogueWork bails")
                return
            }
            print("   chosen: \(album.title)")

            let detailed = try await album.with([.tracks])
            let tracks = detailed.tracks ?? []
            print("   tracks: \(tracks.count)")
            for track in tracks {
                guard case .song(let song) = track else { continue }
                let tier = CatalogueReference.matchTier(title: song.title, reference: reference)
                print("     [tier \(tier)] \(song.title)")
            }
        } catch {
            print("   ERROR: \(error)")
        }
    }
}
#endif
