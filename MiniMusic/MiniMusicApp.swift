import SwiftUI
import MusicKit

@main
struct MiniMusicApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authManager = MusicAuthManager()
    @StateObject private var playerVM = PlayerViewModel()
    @StateObject private var searchVM = MusicSearchViewModel()

    var body: some Scene {
        MenuBarExtra("MiniMusic", systemImage: "music.note") {
            Group {
                if authManager.status == .authorized {
                    PlayerView()
                } else {
                    authView
                }
            }
            .environmentObject(appState)
            .environmentObject(authManager)
            .environmentObject(playerVM)
            .environmentObject(searchVM)
        }
        .menuBarExtraStyle(.window)
    }

    private var authView: some View {
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
