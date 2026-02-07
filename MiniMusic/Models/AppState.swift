import SwiftUI
import MusicKit

enum NavigationDestination: Hashable {
    case player
    case search
    case queue
    case library
}

@MainActor
final class AppState: ObservableObject {
    @Published var authStatus: MusicAuthorization.Status = .notDetermined
    @Published var currentDestination: NavigationDestination = .player
    @Published var isSearchFieldFocused: Bool = false
    @Published var isMenuPresented: Bool = false

    var isAuthorized: Bool {
        authStatus == .authorized
    }
}
