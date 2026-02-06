import Foundation
import MusicKit

@MainActor
final class MusicAuthManager: ObservableObject {
    @Published private(set) var status: MusicAuthorization.Status = .notDetermined

    init() {
        status = MusicAuthorization.currentStatus
    }

    func requestAuthorization() async {
        let result = await MusicAuthorization.request()
        status = result
    }

    var isDeniedOrRestricted: Bool {
        status == .denied || status == .restricted
    }

    var statusMessage: String {
        switch status {
        case .authorized:
            return "Connected to Apple Music."
        case .denied:
            return "Apple Music access was denied. Please enable it in System Settings > Privacy & Security > Media & Apple Music."
        case .restricted:
            return "Apple Music access is restricted on this device."
        case .notDetermined:
            return "Apple Music access has not been requested yet."
        @unknown default:
            return "Unknown authorization status."
        }
    }
}
