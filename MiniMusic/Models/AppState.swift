import SwiftUI
import MusicKit

enum NavigationDestination: Hashable {
    case player
    case search
    case queue
    case library
}

extension Notification.Name {
    static let menuBarDismissed = Notification.Name("MiniMusic.menuBarDismissed")
    static let openSettingsRequested = Notification.Name("MiniMusic.openSettingsRequested")
}

/// Shared panel geometry.
///
/// The dropdown panel auto-sizes to its SwiftUI content
/// (`NSHostingController.sizingOptions = .preferredContentSize`). A `NavigationStack`
/// given only a width has no natural height (it fills its parent), so pairing it with
/// an auto-sizing window is circular — the window sizes to the content while the
/// content sizes to the window — which re-entered layout synchronously and overflowed
/// the stack (SIGSEGV).
///
/// The fix: each screen measures its own intrinsic content height and reports it via
/// `PanelHeightKey`; the panel adopts that value. Content height doesn't depend on the
/// window height, so the size converges instead of looping — and each screen hugs its
/// content (no wasted space) instead of sharing one fixed height.
enum PanelMetrics {
    /// Fallback/initial height and the ceiling every screen is clamped to.
    static let maxHeight: CGFloat = 470
    static let minHeight: CGFloat = 240

    static func clamp(_ height: CGFloat) -> CGFloat {
        max(minHeight, min(height, maxHeight))
    }
}

/// A screen's intrinsic content height, bubbled up to the panel. When two screens are
/// briefly on-screen together (a push/pop transition) the taller one wins.
struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Report this view's measured height as the desired panel height. Apply to the
    /// root content of each navigation screen.
    func reportsPanelHeight() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
            }
        )
    }
}

@Observable final class AppState {
    var authStatus: MusicAuthorization.Status = .notDetermined
    var currentDestination: NavigationDestination = .player
    var isSearchFieldFocused: Bool = false

    /// Set by the AppDelegate; the current screen calls this with its measured
    /// intrinsic height so the panel can resize to hug it. One-way (content → window).
    @ObservationIgnored var requestPanelHeight: ((CGFloat) -> Void)?

    var isAuthorized: Bool {
        authStatus == .authorized
    }
}
