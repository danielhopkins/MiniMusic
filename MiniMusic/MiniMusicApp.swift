import AppKit
import KeyboardShortcuts
import MusicKit
import SwiftUI

@main
struct MiniMusicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The settings window is managed by AppDelegate — SwiftUI's `Settings` scene
    // won't reliably display from a menu bar agent app — so this is just a
    // placeholder to satisfy the App's scene requirement.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Borderless panel that can still become key, so the hosted SwiftUI text field
/// is a real first responder (an `NSPopover` in an agent app can't reliably be
/// the key window, which broke Return/typing in the search field).
final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Owns the menu bar status item and the dropdown panel.
///
/// SwiftUI's `MenuBarExtra` (.window) can't be opened programmatically on macOS 27
/// (its status-item button has no target/action and the content window is created
/// lazily only on a real click), so we manage an `NSStatusItem` + `MenuPanel`
/// directly, hosting the existing SwiftUI views. Opening is a plain
/// `makeKeyAndOrderFront`, fully reliable from the hotkey.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var panel: MenuPanel!

    private let appState = AppState()
    private let authManager = MusicAuthManager()
    private let playerVM = PlayerViewModel()
    private let searchVM = MusicSearchViewModel()
    private let softwareUpdater = SoftwareUpdater()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Debug probe: run one search, print it, exit. No UI.
        if let query = CatalogueProbe.requestedQuery {
            Task { await CatalogueProbe.run(query: query, viewModel: searchVM) }
            return
        }
        if let queries = CatalogueProbe.requestedStationQueries {
            Task { await CatalogueProbe.runStations(queries: queries) }
            return
        }
        if let monitor = CatalogueProbe.requestedLiveMonitor {
            Task { await CatalogueProbe.runLiveMonitor(id: monitor.id, seconds: monitor.seconds) }
            return
        }
        if let queries = CatalogueProbe.requestedPipelineQueries {
            Task { await CatalogueProbe.runPipeline(queries: queries, viewModel: searchVM) }
            return
        }
        #endif

        migrateConflictingShortcut()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "MiniMusic")
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.target = self
        self.statusItem = statusItem

        let root = RootView()
            .environment(appState)
            .environment(authManager)
            .environment(playerVM)
            .environment(searchVM)
            .environment(searchVM.history)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        let panel = MenuPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = .preferredContentSize
        panel.contentViewController = hosting
        panel.delegate = self
        self.panel = panel

        KeyboardShortcuts.onKeyDown(for: .toggleMiniMusic) { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }

        NotificationCenter.default.addObserver(
            forName: .openSettingsRequested, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.openSettings() }
        }

        // Restore the previously saved queue (paused) once MusicKit is ready.
        Task { @MainActor in
            await playerVM.restoreQueueIfNeeded()
        }
    }

    /// Persist the queue on quit so it survives the next launch.
    func applicationWillTerminate(_ notification: Notification) {
        playerVM.persistQueue()
    }

    @objc private func statusItemClicked() {
        toggle()
    }

    private func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    private func show() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        searchVM.searchQuery = ""
        searchVM.clearResults()

        // Anchor just under the status item (clamped on screen). The panel sizes
        // itself from the hosting controller's preferred content size.
        panel.layoutIfNeeded()
        let size = panel.frame.size
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var originX = buttonRect.midX - size.width / 2
        if let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame {
            originX = min(max(originX, visible.minX + 8), visible.maxX - size.width - 8)
        }
        panel.setFrameOrigin(NSPoint(x: originX, y: buttonRect.minY - size.height - 4))

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            appState.isSearchFieldFocused = true
        }
    }

    private func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        searchVM.searchQuery = ""
        searchVM.clearResults()
        NotificationCenter.default.post(name: .menuBarDismissed, object: nil)
    }

    private func openSettings() {
        hide()
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView().environment(softwareUpdater))
            let window = NSWindow(contentViewController: controller)
            window.title = "MiniMusic Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: NSWindowDelegate

    /// Dismiss when focus leaves the panel (click in another app, etc.).
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    /// Ctrl+Space collides with macOS's input-source switcher, so a persisted value
    /// of it left the hotkey effectively dead. Move it to the intended default
    /// (Option+Space). Custom user shortcuts are left untouched.
    private func migrateConflictingShortcut() {
        let conflicting = KeyboardShortcuts.Shortcut(.space, modifiers: [.control])
        if KeyboardShortcuts.getShortcut(for: .toggleMiniMusic) == conflicting {
            KeyboardShortcuts.setShortcut(.init(.space, modifiers: [.option]), for: .toggleMiniMusic)
        }
    }
}

/// Switches between the player and the Apple Music authorization prompt.
struct RootView: View {
    @Environment(MusicAuthManager.self) private var authManager

    var body: some View {
        Group {
            if authManager.status == .authorized {
                PlayerView()
            } else {
                AuthView()
            }
        }
    }
}

struct AuthView: View {
    @Environment(MusicAuthManager.self) private var authManager

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("MiniMusic")
                .font(.title2)
                .fontWeight(.semibold)

            Text(authManager.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if authManager.status == .notDetermined {
                Button("Connect Apple Music") {
                    Task {
                        await authManager.requestAuthorization()
                    }
                }
                .buttonStyle(.borderedProminent)
            } else if authManager.status == .denied {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }

            Divider()

            Button("Quit MiniMusic") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
        }
        .frame(width: 280, height: 300)
        .padding()
        .task {
            if authManager.status == .notDetermined {
                await authManager.requestAuthorization()
            }
        }
    }
}
