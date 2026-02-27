import AppKit
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class PreferencesWindowController: NSWindowController {
    var onAliasesUpdated: (() -> Void)?
    var onFilterUpdated: ((AppFilterMode, [String]) -> Void)?

    private let settingsStore = AppSettingsStore.shared

    private let launchAtLoginButton = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let filterModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let appFilterTextView = NSTextView()
    private let aliasesTextView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "SlackmojiEverywhere Preferences"
        window.center()

        super.init(window: window)

        setupUI()
        loadState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.spacing = 10
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])

        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(handleLaunchAtLoginToggle)
        rootStack.addArrangedSubview(launchAtLoginButton)

        let filterModeRow = NSStackView()
        filterModeRow.orientation = .horizontal
        filterModeRow.alignment = .centerY
        filterModeRow.spacing = 8

        let filterModeLabel = NSTextField(labelWithString: "App filter mode:")
        filterModeRow.addArrangedSubview(filterModeLabel)
        filterModeRow.addArrangedSubview(filterModePopup)

        for mode in AppFilterMode.allCases {
            filterModePopup.addItem(withTitle: mode.title)
            filterModePopup.lastItem?.representedObject = mode.rawValue
        }

        rootStack.addArrangedSubview(filterModeRow)

        let appFilterLabel = NSTextField(labelWithString: "Bundle IDs (one per line, used by allow/deny list):")
        rootStack.addArrangedSubview(appFilterLabel)

        let appFilterScroll = NSScrollView()
        appFilterScroll.hasVerticalScroller = true
        appFilterScroll.borderType = .bezelBorder
        appFilterTextView.isRichText = false
        appFilterTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        appFilterScroll.documentView = appFilterTextView
        appFilterScroll.heightAnchor.constraint(equalToConstant: 120).isActive = true
        rootStack.addArrangedSubview(appFilterScroll)

        let aliasesLabel = NSTextField(labelWithString: "Custom aliases JSON:")
        rootStack.addArrangedSubview(aliasesLabel)

        let aliasesScroll = NSScrollView()
        aliasesScroll.hasVerticalScroller = true
        aliasesScroll.borderType = .bezelBorder
        aliasesTextView.isRichText = false
        aliasesTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        aliasesScroll.documentView = aliasesTextView
        aliasesScroll.heightAnchor.constraint(equalToConstant: 320).isActive = true
        rootStack.addArrangedSubview(aliasesScroll)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let importButton = NSButton(title: "Import…", target: self, action: #selector(importAliases))
        let exportButton = NSButton(title: "Export…", target: self, action: #selector(exportAliases))
        let saveButton = NSButton(title: "Save Preferences", target: self, action: #selector(savePreferences))

        buttonRow.addArrangedSubview(importButton)
        buttonRow.addArrangedSubview(exportButton)
        buttonRow.addArrangedSubview(NSView())
        buttonRow.addArrangedSubview(saveButton)
        rootStack.addArrangedSubview(buttonRow)

        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        statusLabel.textColor = .secondaryLabelColor
        rootStack.addArrangedSubview(statusLabel)
    }

    private func loadState() {
        let launchAtLoginEnabled = (SMAppService.mainApp.status == .enabled) || settingsStore.launchAtLoginEnabled
        settingsStore.launchAtLoginEnabled = launchAtLoginEnabled
        launchAtLoginButton.state = launchAtLoginEnabled ? .on : .off

        if let selectedItem = filterModePopup.itemArray.first(where: {
            ($0.representedObject as? String) == settingsStore.appFilterMode.rawValue
        }) {
            filterModePopup.select(selectedItem)
        }

        appFilterTextView.string = settingsStore.bundleIDsText(from: settingsStore.appFilterBundleIDs)

        if let aliasesText = try? EmojiAliasStore.readCustomAliasesJSONString() {
            aliasesTextView.string = aliasesText
        } else {
            aliasesTextView.string = "{\n  \"partyparrot\": \"🦜\"\n}"
        }
    }

    @objc
    private func handleLaunchAtLoginToggle() {
        do {
            if launchAtLoginButton.state == .on {
                try SMAppService.mainApp.register()
                settingsStore.launchAtLoginEnabled = true
                statusLabel.stringValue = "Launch at login enabled."
            } else {
                try SMAppService.mainApp.unregister()
                settingsStore.launchAtLoginEnabled = false
                statusLabel.stringValue = "Launch at login disabled."
            }
        } catch {
            launchAtLoginButton.state = settingsStore.launchAtLoginEnabled ? .on : .off
            statusLabel.stringValue = "Launch at login update failed: \(error.localizedDescription)"
        }
    }

    @objc
    private func importAliases() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            aliasesTextView.string = try String(contentsOf: url, encoding: .utf8)
            statusLabel.stringValue = "Imported aliases from \(url.lastPathComponent)."
        } catch {
            statusLabel.stringValue = "Import failed: \(error.localizedDescription)"
        }
    }

    @objc
    private func exportAliases() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "custom_aliases.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try aliasesTextView.string.write(to: url, atomically: true, encoding: .utf8)
            statusLabel.stringValue = "Exported aliases to \(url.lastPathComponent)."
        } catch {
            statusLabel.stringValue = "Export failed: \(error.localizedDescription)"
        }
    }

    @objc
    private func savePreferences() {
        do {
            try EmojiAliasStore.saveCustomAliasesJSONString(aliasesTextView.string)
        } catch {
            statusLabel.stringValue = "Custom aliases JSON is invalid: \(error.localizedDescription)"
            return
        }

        let selectedModeRawValue = filterModePopup.selectedItem?.representedObject as? String
        let mode = AppFilterMode(rawValue: selectedModeRawValue ?? "") ?? .off
        let bundleIDs = settingsStore.parseBundleIDs(from: appFilterTextView.string)

        settingsStore.appFilterMode = mode
        settingsStore.appFilterBundleIDs = bundleIDs

        appFilterTextView.string = settingsStore.bundleIDsText(from: bundleIDs)
        onFilterUpdated?(mode, bundleIDs)
        onAliasesUpdated?()

        statusLabel.stringValue = "Preferences saved."
    }
}
