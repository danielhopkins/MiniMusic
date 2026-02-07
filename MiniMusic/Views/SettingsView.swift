import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Form {
                KeyboardShortcuts.Recorder("Open MiniMusic:", name: .toggleMiniMusic)
                LabeledContent("Version", value: appVersion)
            }
            .formStyle(.columns)

            Divider()

            VStack(spacing: 6) {
                Text("MiniMusic was created by Dan Hopkins")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Link(destination: URL(string: "https://about.me/dhop")!) {
                        Text("about.me/dhop")
                    }
                    Link(destination: URL(string: "https://github.com/danielhopkins/MiniMusic")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "cat.fill")
                            Text("GitHub")
                        }
                    }
                }
                .font(.callout)
            }

            Divider()

            Button("Quit MiniMusic") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 300)
    }
}
