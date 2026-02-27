import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import ServiceManagement
import SlackmojiCore

enum EmojiAliasStore {
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

    static func customAliasesURL() -> URL? {
        ensureCustomAliasesFileExists()
    }

    static func readCustomAliasesJSONString() throws -> String {
        guard let fileURL = ensureCustomAliasesFileExists() else {
            throw CocoaError(.fileNoSuchFile)
        }

        let data = try Data(contentsOf: fileURL)
        let aliases = try JSONDecoder().decode([String: String].self, from: data)
        let normalized = normalizedAliases(from: aliases)
        let formatted = try formattedJSONData(from: normalized)

        guard var json = String(data: formatted, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        if !json.hasSuffix("\n") {
            json.append("\n")
        }

        return json
    }

    static func saveCustomAliasesJSONString(_ jsonString: String) throws {
        guard let fileURL = ensureCustomAliasesFileExists() else {
            throw CocoaError(.fileNoSuchFile)
        }

        guard let inputData = jsonString.data(using: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let aliases = try JSONDecoder().decode([String: String].self, from: inputData)
        let normalized = normalizedAliases(from: aliases)

        var formatted = try formattedJSONData(from: normalized)
        if formatted.last != 0x0A {
            formatted.append(0x0A)
        }

        try formatted.write(to: fileURL, options: [.atomic])
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

    private static func formattedJSONData(from aliases: [String: String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: aliases, options: [.prettyPrinted, .sortedKeys])
    }

    static func customAliasesFileURL() -> URL? {
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
    private let maxBufferSize = 220
    private let injectedEventMarker: Int64 = 0x534D4A59
    private var aliases = EmojiAliasStore.loadAliases()
    private var appFilterMode: AppFilterMode = .off
    private var appFilterBundleIDs = Set<String>()

    var onReplacement: ((String, String) -> Void)?

    func reloadAliases() {
        aliases = EmojiAliasStore.loadAliases()
    }

    func updateFiltering(mode: AppFilterMode, bundleIDs: [String]) {
        appFilterMode = mode
        appFilterBundleIDs = Set(bundleIDs.map { $0.lowercased() })
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

        if event.getIntegerValueField(.eventSourceUserData) == injectedEventMarker {
            return Unmanaged.passUnretained(event)
        }

        guard shouldProcessCurrentContext() else {
            typedBuffer.removeAll(keepingCapacity: true)
            return Unmanaged.passUnretained(event)
        }

        processKeyDown(event)
        return Unmanaged.passUnretained(event)
    }

    private func processKeyDown(_ event: CGEvent) {
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            typedBuffer.removeAll(keepingCapacity: true)
            return
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == Int64(kVK_Delete) {
            if !typedBuffer.isEmpty {
                typedBuffer.removeLast()
            }
            return
        }

        switch keyCode {
        case Int64(kVK_Return), Int64(kVK_Tab), Int64(kVK_Escape), Int64(kVK_Space):
            typedBuffer.removeAll(keepingCapacity: true)
            return
        case Int64(kVK_LeftArrow), Int64(kVK_RightArrow), Int64(kVK_UpArrow), Int64(kVK_DownArrow):
            typedBuffer.removeAll(keepingCapacity: true)
            return
        default:
            break
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

        if EmojiAliasMatcher.isAllowedAliasScalar(scalar) {
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
        guard let match = EmojiAliasMatcher.bestMatch(in: typedBuffer, aliases: aliases) else { return }

        injectReplacement(removingCharacters: match.alias.count + 2, replacement: match.replacement)
        typedBuffer.removeAll(keepingCapacity: true)
        onReplacement?(match.alias, match.replacement)
    }

    private func injectReplacement(removingCharacters count: Int, replacement: String) {
        guard count > 0 else { return }

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

        keyDown.setIntegerValueField(.eventSourceUserData, value: injectedEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: injectedEventMarker)

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

        keyDown.setIntegerValueField(.eventSourceUserData, value: injectedEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: injectedEventMarker)
        keyDown.keyboardSetUnicodeString(stringLength: codeUnits.count, unicodeString: &codeUnits)
        keyUp.keyboardSetUnicodeString(stringLength: codeUnits.count, unicodeString: &codeUnits)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func shouldProcessCurrentContext() -> Bool {
        guard !isFocusedElementSecureInput() else { return false }

        let currentBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased()

        switch appFilterMode {
        case .off:
            return true
        case .allowlist:
            guard let currentBundleID else { return false }
            return appFilterBundleIDs.contains(currentBundleID)
        case .denylist:
            guard let currentBundleID else { return true }
            return !appFilterBundleIDs.contains(currentBundleID)
        }
    }

    private func isFocusedElementSecureInput() -> Bool {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?

        let focusedResult = AXUIElementCopyAttributeValue(
            systemWideElement,
            "AXFocusedUIElement" as CFString,
            &focusedObject
        )

        guard focusedResult == .success,
              let focusedObject,
              CFGetTypeID(focusedObject) == AXUIElementGetTypeID()
        else {
            return false
        }

        let focusedElement = focusedObject as! AXUIElement

        var protectedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(focusedElement, "AXValueProtected" as CFString, &protectedValue) == .success,
           let isProtected = protectedValue as? Bool,
           isProtected {
            return true
        }

        var subroleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(focusedElement, "AXSubrole" as CFString, &subroleValue) == .success,
           let subrole = subroleValue as? String,
           subrole == "AXSecureTextField" {
            return true
        }

        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(focusedElement, "AXRole" as CFString, &roleValue) == .success,
           let role = roleValue as? String,
           role == "AXSecureTextField" {
            return true
        }

        return false
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
    private let settingsStore = AppSettingsStore.shared

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let enableItem = NSMenuItem(title: "Enable Emoji Expansion", action: #selector(toggleEnabled), keyEquivalent: "")
    private let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
    private let accessibilityItem = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let customAliasesItem = NSMenuItem(title: "Open Custom Aliases…", action: #selector(openCustomAliasesFile), keyEquivalent: "")
    private let reloadAliasesItem = NSMenuItem(title: "Reload Aliases", action: #selector(reloadAliases), keyEquivalent: "")
    private var preferencesWindowController: PreferencesWindowController?

    private var isEnabled = true {
        didSet { updateMenuState() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = EmojiAliasStore.ensureCustomAliasesFileExists()
        monitor.reloadAliases()
        monitor.updateFiltering(mode: settingsStore.appFilterMode, bundleIDs: settingsStore.appFilterBundleIDs)

        if settingsStore.launchAtLoginEnabled {
            try? SMAppService.mainApp.register()
        }

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
        preferencesItem.target = self
        accessibilityItem.target = self
        customAliasesItem.target = self
        reloadAliasesItem.target = self

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(enableItem)
        menu.addItem(preferencesItem)
        menu.addItem(.separator())
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
        guard let fileURL = EmojiAliasStore.customAliasesURL() else { return }
        NSWorkspace.shared.open(fileURL)
    }

    @objc
    private func reloadAliases() {
        monitor.reloadAliases()
    }

    @objc
    private func openPreferences() {
        if preferencesWindowController == nil {
            let controller = PreferencesWindowController()
            controller.onAliasesUpdated = { [weak self] in
                self?.monitor.reloadAliases()
            }
            controller.onFilterUpdated = { [weak self] mode, bundleIDs in
                self?.monitor.updateFiltering(mode: mode, bundleIDs: bundleIDs)
            }
            preferencesWindowController = controller
        }

        preferencesWindowController?.present()
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
