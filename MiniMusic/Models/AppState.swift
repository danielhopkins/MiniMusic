import SwiftUI
import MusicKit

enum NavigationDestination: Hashable {
    case player
    case search
    case queue
    case library
}

@MainActor
@Observable final class AppState {
    var authStatus: MusicAuthorization.Status = .notDetermined
    var currentDestination: NavigationDestination = .player
    var isSearchFieldFocused: Bool = false
    var isMenuPresented: Bool = false

    var isAuthorized: Bool {
        authStatus == .authorized
    }
}
