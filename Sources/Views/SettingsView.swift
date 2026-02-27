import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var customAliasesText: String = ""
    @State private var bundleIDsText: String = ""
    @State private var statusMessage: String = ""
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            generalSection
            Divider()
            appFilterSection
            Divider()
            customAliasesSection
            statusBar
        }
        .padding(18)
        .frame(width: 760, height: 680)
        .onAppear { loadState() }
    }

    @ViewBuilder
    private var generalSection: some View {
        Toggle("Launch at login", isOn: $appState.launchAtLogin)
            .toggleStyle(.checkbox)
    }

    @ViewBuilder
    private var appFilterSection: some View {
        HStack {
            Text("App filter mode:")
            Picker("", selection: $appState.appFilterMode) {
                ForEach(AppFilterMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 150)
        }

        Text("Bundle IDs (one per line, used by allow/deny list):")
            .font(.caption)
            .foregroundStyle(.secondary)

        TextEditor(text: $bundleIDsText)
            .font(.system(.body, design: .monospaced))
            .frame(height: 100)
            .border(Color.secondary.opacity(0.3))
    }

    @ViewBuilder
    private var customAliasesSection: some View {
        Text("Custom aliases JSON:")
            .font(.caption)
            .foregroundStyle(.secondary)

        TextEditor(text: $customAliasesText)
            .font(.system(.body, design: .monospaced))
            .frame(maxHeight: .infinity)
            .border(Color.secondary.opacity(0.3))

        HStack {
            Button("Import…") { isImporting = true }
            Button("Export…") { exportAliases() }
            Spacer()
            Button("Save Preferences") { savePreferences() }
                .keyboardShortcut(.defaultAction)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result,
               let content = try? String(contentsOf: url, encoding: .utf8)
            {
                customAliasesText = content
                statusMessage = "Imported aliases from \(url.lastPathComponent)."
            }
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        if !statusMessage.isEmpty {
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func loadState() {
        bundleIDsText = AppSettingsStore.shared.bundleIDsText(
            from: appState.appFilterBundleIDs)
        if let json = try? EmojiMap.readCustomAliasesJSON() {
            customAliasesText = json
        } else {
            customAliasesText = "{\n  \"partyparrot\": \"🦜\"\n}\n"
        }
    }

    private func savePreferences() {
        do {
            try EmojiMap.saveCustomAliasesJSON(customAliasesText)
        } catch {
            statusMessage = "Custom aliases JSON is invalid: \(error.localizedDescription)"
            return
        }

        let bundleIDs = AppSettingsStore.shared.parseBundleIDs(from: bundleIDsText)
        appState.appFilterBundleIDs = bundleIDs
        bundleIDsText = AppSettingsStore.shared.bundleIDsText(from: bundleIDs)

        appState.reloadAliases()
        statusMessage = "Preferences saved."
    }

    private func exportAliases() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "custom_aliases.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try customAliasesText.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Exported aliases to \(url.lastPathComponent)."
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Window presentation

    private static var settingsWindow: NSWindow?

    static func show(appState: AppState) {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(appState: appState)
        let hostingController = NSHostingController(rootView: view)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "SlackmojiEverywhere Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}
