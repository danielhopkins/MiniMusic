import Foundation
import Sparkle

@Observable
final class SoftwareUpdater {
    var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        observation = updaterController.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            self?.canCheckForUpdates = updater.canCheckForUpdates
        }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
