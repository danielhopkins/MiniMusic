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
}

@Observable final class AppState {
    var authStatus: MusicAuthorization.Status = .notDetermined
    var currentDestination: NavigationDestination = .player
    var isSearchFieldFocused: Bool = false
    var isMenuPresented: Bool = false

    @ObservationIgnored var globalClickMonitor: Any?

    var isAuthorized: Bool {
        authStatus == .authorized
    }
}
