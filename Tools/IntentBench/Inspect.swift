import Foundation
import FoundationModels

// Ad-hoc inspector for the on-device intent parser.
//
// Runs the real `SearchIntentParser` on the queries you pass (or a default set),
// then prints the parsed facets and the downstream search consequences the
// planner + view model would apply (route, catalog fetch limit, display cap,
// vibe re-rank). Use it to see exactly what a query turns into.
//
//   ./inspect.sh "brahms piano" "taylor swift songs"
//
// Requires a Mac with Apple Intelligence enabled. See README.md.

// Mirror of MusicSearchViewModel's fetch-limit + display-cap logic, kept here so
// the inspector can report the real downstream effect of the facets. Keep in sync
// with MusicSearchViewModel.performCatalogSearch / allResults if those change.
func downstream(for facets: SearchFacets, strategy: SearchStrategy) -> String {
    let categoriesEmpty = facets.categories.isEmpty
    let descriptorEmpty = facets.descriptor.trimmingCharacters(in: .whitespaces).isEmpty

    switch strategy {
    case .text:
        let fetch = categoriesEmpty ? (descriptorEmpty ? 6 : 25) : 25
        let cap = categoriesEmpty ? "3 per category" : "uncapped"
        let rerank = descriptorEmpty ? "no" : "YES (rerankByVibe(\"\(facets.descriptor)\"))"
        return "route=text  catalogFetch=\(fetch) total  displayCap=\(cap)  vibeRerank=\(rerank)"
    case .artistTopSongs:
        return "route=artistTopSongs  (artist-scoped, uncapped)"
    case .artistAlbums:
        return "route=artistAlbums  (artist-scoped, uncapped)"
    case .albumTracks:
        return "route=albumTracks  (album-scoped)"
    }
}

func report(_ q: String, _ intent: SearchIntent?) {
    print("──────────────────────────────────────────────────────")
    print("QUERY: \"\(q)\"")
    guard let intent else {
        print("  model returned nil (unavailable / rejected / cancelled) → deterministic fallback")
        let f = SearchFacets(deterministicallyParsing: q)
        print("  fallback facets: term=\"\(f.term)\" categories=\(f.categories.map(\.rawValue))")
        print("  \(downstream(for: f, strategy: SearchPlanner.plan(f)))")
        return
    }
    let f = intent.facets
    print("  term:       \"\(f.term)\"")
    print("  descriptor: \"\(f.descriptor)\"   \(f.descriptor.isEmpty ? "" : "⚠️ triggers vibe rerank")")
    print("  artist:     \"\(f.artist)\"")
    print("  album:      \"\(f.album)\"")
    print("  song:       \"\(f.song)\"")
    print("  categories: \(f.categories.map(\.rawValue))")
    print("  → \(downstream(for: f, strategy: SearchPlanner.plan(f)))")
}

@main
struct Inspect {
    static func main() async {
        let parser = SearchIntentParser()
        print("model available: \(parser.isAvailable)")

        let queries: [String] = CommandLine.arguments.count > 1
            ? Array(CommandLine.arguments.dropFirst())
            : [
                "brahms piano",
                "brahms",
                "mahler symphony",
                "chopin nocturne",
                "exciting classical playlists",
                "taylor swift songs",
                "relaxing jazz",
              ]

        for q in queries {
            report(q, await parser.parse(q))
        }
        print("──────────────────────────────────────────────────────")
    }
}
