import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Open MiniMusic:", name: .toggleMiniMusic)
        }
        .formStyle(.columns)
        .padding()
        .frame(width: 300)
    }
}
