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

@Observable final class AppState {
    var authStatus: MusicAuthorization.Status = .notDetermined
    var currentDestination: NavigationDestination = .player
    var isSearchFieldFocused: Bool = false

    var isAuthorized: Bool {
        authStatus == .authorized
    }
}
