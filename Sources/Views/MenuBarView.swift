import SwiftUI

struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Enable Emoji Expansion", isOn: $appState.isEnabled)
                .toggleStyle(.checkbox)
                .disabled(!appState.accessibilityManager.isTrusted)

            Divider()

            permissionSection

            if !appState.recentReplacements.isEmpty {
                Divider()
                recentReplacementsSection
            }

            Divider()

            Button("Preferences…") {
                SettingsView.show(appState: appState)
            }
            .keyboardShortcut(",")

            Button("Open Custom Aliases…") {
                openCustomAliasesFile()
            }

            Button("Reload Aliases") {
                appState.reloadAliases()
            }

            Divider()

            Button("Quit SlackmojiEverywhere") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if appState.accessibilityManager.isTrusted {
            Label("Accessibility Permission Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
        } else {
            Button("Open Accessibility Settings…") {
                appState.accessibilityManager.openAccessibilitySettings()
            }
        }
    }

    @ViewBuilder
    private var recentReplacementsSection: some View {
        Text("Recent")
            .font(.caption)
            .foregroundStyle(.secondary)

        ForEach(appState.recentReplacements) { replacement in
            HStack {
                Text(replacement.emoji)
                Text(":\(replacement.alias):")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    private func openCustomAliasesFile() {
        guard let url = EmojiMap.customAliasesFileURL() else { return }
        _ = EmojiMap.ensureCustomAliasesFileExists()
        NSWorkspace.shared.open(url)
    }
}
