import SwiftUI

/// Placeholder text for the search field that opens with an instruction, then
/// slowly cross-fades through example natural-language queries on a loop — a
/// hint that you can ask for songs, artists, and moods however you like.
///
/// Rendered as an overlay behind the (empty) text field, so it disappears the
/// moment the user starts typing.
struct RotatingSearchPrompt: View {
    /// Index 0 is the standing instruction; the rest are example queries the
    /// loop fades through before returning to it.
    static let phrases: [String] = [
        "Ask for any song, artist or mood",
        "Upbeat songs for a morning run",
        "Something mellow for studying",
        "90s hip hop classics",
        "Rainy day jazz",
        "Taylor Swift's latest album",
        "Feel-good road trip playlist",
        "Relaxing piano for focus",
        "Dance hits from the 80s",
        "Acoustic covers of pop songs",
    ]

    private static let interval: TimeInterval = 3.5

    @State private var index = 0
    private let timer = Timer.publish(every: interval, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(Self.phrases[index])
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .contentTransition(.opacity)
            .onReceive(timer) { _ in
                withAnimation(.easeInOut(duration: 0.7)) {
                    index = (index + 1) % Self.phrases.count
                }
            }
            .accessibilityHidden(true)
    }
}
