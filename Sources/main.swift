import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

private enum EmojiAliasStore {
    private static let bundledAliasesFile = "slack_emoji_aliases"
    private static let customAliasesFile = "custom_aliases.json"
    private static let appSupportFolder = "SlackmojiEverywhere"

    static func loadAliases() -> [String: String] {
        let bundled = bundledAliases()
        let custom = customAliases()
        return bundled.merging(custom) { _, customValue in customValue }
    }

    static func ensureCustomAliasesFileExists() -> URL? {
        guard let fileURL = customAliasesFileURL() else { return nil }

        let directoryURL = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            return fileURL
        }

        let template: [String: String] = [
            "partyparrot": "🦜",
            "shipit": "🚢",
            "shruggie": "¯\\_(ツ)_/¯"
        ]

        if let data = try? JSONEncoder().encode(template) {
            try? data.write(to: fileURL, options: [.atomic])
        }

        return fileURL
    }

    private static func bundledAliases() -> [String: String] {
        guard
            let url = Bundle.module.url(forResource: bundledAliasesFile, withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let aliases = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }

        return normalizedAliases(from: aliases)
    }

    private static func customAliases() -> [String: String] {
        guard
            let fileURL = ensureCustomAliasesFileExists(),
            let data = try? Data(contentsOf: fileURL),
            let aliases = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }

        return normalizedAliases(from: aliases)
    }

    private static func normalizedAliases(from aliases: [String: String]) -> [String: String] {
        var normalized: [String: String] = [:]
        normalized.reserveCapacity(aliases.count)

        for (key, value) in aliases {
            let alias = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let replacement = value.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !alias.isEmpty, !replacement.isEmpty else { continue }
            normalized[alias] = replacement
        }

        return normalized
    }

    private static func customAliasesFileURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        return appSupport
            .appendingPathComponent(appSupportFolder, isDirectory: true)
            .appendingPathComponent(customAliasesFile, isDirectory: false)
    }
}

private final class GlobalTypingMonitor {
    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<GlobalTypingMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        return monitor.handle(type: type, event: event)
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var typedBuffer = ""
    private let maxBufferSize = 160
    private var suppressUntil = Date.distantPast
    private var aliases = EmojiAliasStore.loadAliases()

    var onReplacement: ((String, String) -> Void)?

    func reloadAliases() {
        aliases = EmojiAliasStore.loadAliases()
    }

    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.tapDisabledByTimeout.rawValue)
            | (CGEventMask(1) << CGEventType.tapDisabledByUserInput.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        runLoopSource = nil
        eventTap = nil
        typedBuffer.removeAll(keepingCapacity: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        if Date() < suppressUntil {
            return Unmanaged.passUnretained(event)
        }

        processKeyDown(event)
        return Unmanaged.passUnretained(event)
    }

    private func processKeyDown(_ event: CGEvent) {
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == Int64(kVK_Delete) {
            if !typedBuffer.isEmpty {
                typedBuffer.removeLast()
            }
            return
        }

        guard let text = event.unicodeText, !text.isEmpty else {
            return
        }

        for scalar in text.unicodeScalars {
            consume(scalar)
        }
    }

    private func consume(_ scalar: UnicodeScalar) {
        let character = Character(scalar)

        if character == ":" {
            typedBuffer.append(character)
            trimBufferIfNeeded()
            attemptReplacementIfNeeded()
            return
        }

        if scalar.properties.isWhitespace {
            typedBuffer.removeAll(keepingCapacity: true)
            return
        }

        if isAllowedAliasScalar(scalar) {
            typedBuffer.append(character)
            trimBufferIfNeeded()
            return
        }

        typedBuffer.removeAll(keepingCapacity: true)
    }

    private func trimBufferIfNeeded() {
        guard typedBuffer.count > maxBufferSize else { return }

        let trimCount = typedBuffer.count - maxBufferSize
        typedBuffer.removeFirst(trimCount)
    }

    private func attemptReplacementIfNeeded() {
        guard typedBuffer.last == ":" else { return }

        let withoutClosingColon = typedBuffer.dropLast()
        var bestMatch: (alias: String, replacement: String)?

        var index = withoutClosingColon.startIndex
        while index < withoutClosingColon.endIndex {
            defer { index = withoutClosingColon.index(after: index) }

            guard withoutClosingColon[index] == ":" else { continue }

            let aliasStart = withoutClosingColon.index(after: index)
            let alias = String(withoutClosingColon[aliasStart...]).lowercased()

            guard !alias.isEmpty, alias.count <= 80 else { continue }
            guard isValidAlias(alias) else { continue }
            guard let replacement = aliases[alias] else { continue }

            if bestMatch == nil || alias.count > bestMatch!.alias.count {
                bestMatch = (alias, replacement)
            }
        }

        guard let match = bestMatch else { return }

        injectReplacement(removingCharacters: match.alias.count + 2, replacement: match.replacement)
        typedBuffer.removeAll(keepingCapacity: true)
        onReplacement?(match.alias, match.replacement)
    }

    private func injectReplacement(removingCharacters count: Int, replacement: String) {
        guard count > 0 else { return }

        suppressUntil = Date().addingTimeInterval(0.2)

        for _ in 0..<count {
            postKey(keyCode: CGKeyCode(kVK_Delete))
        }

        postText(replacement)
    }

    private func postKey(keyCode: CGKeyCode) {
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func postText(_ text: String) {
        var codeUnits = Array(text.utf16)
        guard !codeUnits.isEmpty else { return }

        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            return
        }

        keyDown.keyboardSetUnicodeString(stringLength: codeUnits.count, unicodeString: &codeUnits)
        keyUp.keyboardSetUnicodeString(stringLength: codeUnits.count, unicodeString: &codeUnits)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func isAllowedAliasScalar(_ scalar: UnicodeScalar) -> Bool {
        guard scalar.value < 128 else { return false }

        switch scalar.value {
        case 48...57, 65...90, 97...122:
            return true
        case 43, 45, 95:
            return true
        default:
            return false
        }
    }

    private func isValidAlias(_ alias: String) -> Bool {
        let scalars = Array(alias.unicodeScalars)
        guard !scalars.isEmpty else { return false }

        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]

            if isAllowedAliasScalar(scalar) {
                index += 1
                continue
            }

            if scalar.value == 58 {
                guard index + 1 < scalars.count, scalars[index + 1].value == 58 else {
                    return false
                }
                index += 2
                continue
            }

            return false
        }

        return true
    }
}

private extension CGEvent {
    var unicodeText: String? {
        var characters = [UniChar](repeating: 0, count: 8)
        var count = 0
        keyboardGetUnicodeString(
            maxStringLength: characters.count,
            actualStringLength: &count,
            unicodeString: &characters
        )

        guard count > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: count)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = GlobalTypingMonitor()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let enableItem = NSMenuItem(title: "Enable Emoji Expansion", action: #selector(toggleEnabled), keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let customAliasesItem = NSMenuItem(title: "Open Custom Aliases…", action: #selector(openCustomAliasesFile), keyEquivalent: "")
    private let reloadAliasesItem = NSMenuItem(title: "Reload Aliases", action: #selector(reloadAliases), keyEquivalent: "")

    private var isEnabled = true {
        didSet { updateMenuState() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = EmojiAliasStore.ensureCustomAliasesFileExists()
        monitor.reloadAliases()
        setupMenuBar()

        monitor.onReplacement = { [weak self] _, emoji in
            guard let self else { return }
            DispatchQueue.main.async {
                self.statusItem.button?.title = emoji
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    self?.updateMenuState()
                }
            }
        }

        requestAccessibilityPermissionIfNeeded()
        startMonitoringIfPossible()
        updateMenuState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    func menuWillOpen(_ menu: NSMenu) {
        if isEnabled {
            startMonitoringIfPossible()
        }
        updateMenuState()
    }

    private func setupMenuBar() {
        statusItem.button?.title = "😄"

        enableItem.target = self
        accessibilityItem.target = self
        customAliasesItem.target = self
        reloadAliasesItem.target = self

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(enableItem)
        menu.addItem(accessibilityItem)
        menu.addItem(customAliasesItem)
        menu.addItem(reloadAliasesItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit SlackmojiEverywhere", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func requestAccessibilityPermissionIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func startMonitoringIfPossible() {
        guard isEnabled else { return }
        guard AXIsProcessTrusted() else { return }
        _ = monitor.start()
    }

    private func updateMenuState() {
        let hasAccessibilityPermission = AXIsProcessTrusted()

        enableItem.state = isEnabled ? .on : .off
        enableItem.isEnabled = hasAccessibilityPermission

        if hasAccessibilityPermission {
            accessibilityItem.title = "Accessibility Permission Granted"
            accessibilityItem.isEnabled = false
        } else {
            accessibilityItem.title = "Open Accessibility Settings…"
            accessibilityItem.isEnabled = true
        }

        if !hasAccessibilityPermission {
            statusItem.button?.title = "⚠️"
        } else {
            statusItem.button?.title = isEnabled ? "😄" : "😴"
        }
    }

    @objc
    private func toggleEnabled() {
        isEnabled.toggle()
        if isEnabled {
            startMonitoringIfPossible()
        } else {
            monitor.stop()
        }
    }

    @objc
    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc
    private func openCustomAliasesFile() {
        guard let fileURL = EmojiAliasStore.ensureCustomAliasesFileExists() else { return }
        NSWorkspace.shared.open(fileURL)
    }

    @objc
    private func reloadAliases() {
        monitor.reloadAliases()
    }

    @objc
    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
withExtendedLifetime(delegate) {
    app.run()
}
