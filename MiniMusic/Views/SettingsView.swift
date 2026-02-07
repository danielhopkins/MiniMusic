import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Open MiniMusic:", name: .toggleMiniMusic)
        }
        .formStyle(.grouped)
        .frame(width: 300, height: 100)
    }
}
