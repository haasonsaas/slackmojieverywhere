import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import SlackmojiCore

final class KeyboardMonitor {
    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        return monitor.handle(type: type, event: event)
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var typedBuffer = ""
    private let maxBufferSize = 220
    private let injectedEventMarker: Int64 = 0x534D4A59

    private var aliases: [String: String] = [:]
    private var appFilterMode: AppFilterMode = .off
    private var appFilterBundleIDs = Set<String>()

    var onReplacement: ((_ alias: String, _ emoji: String) -> Void)?

    func updateAliases(_ newAliases: [String: String]) {
        aliases = newAliases
    }

    func updateFiltering(mode: AppFilterMode, bundleIDs: [String]) {
        appFilterMode = mode
        appFilterBundleIDs = Set(bundleIDs.map { $0.lowercased() })
    }

    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.rightMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.tapDisabledByTimeout.rawValue)
            | (CGEventMask(1) << CGEventType.tapDisabledByUserInput.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

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

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .leftMouseDown || type == .rightMouseDown {
            typedBuffer.removeAll(keepingCapacity: true)
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

        return processKeyDown(event)
    }

    private func processKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl)
            || flags.contains(.maskAlternate)
        {
            typedBuffer.removeAll(keepingCapacity: true)
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if keyCode == Int64(kVK_Delete) {
            if !typedBuffer.isEmpty { typedBuffer.removeLast() }
            return Unmanaged.passUnretained(event)
        }

        switch keyCode {
        case Int64(kVK_Return), Int64(kVK_Tab), Int64(kVK_Escape), Int64(kVK_Space):
            typedBuffer.removeAll(keepingCapacity: true)
            return Unmanaged.passUnretained(event)
        case Int64(kVK_LeftArrow), Int64(kVK_RightArrow), Int64(kVK_UpArrow),
            Int64(kVK_DownArrow):
            typedBuffer.removeAll(keepingCapacity: true)
            return Unmanaged.passUnretained(event)
        default:
            break
        }

        guard let text = event.unicodeText, !text.isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        for scalar in text.unicodeScalars {
            if let result = consume(scalar, event: event) {
                return result
            }
        }

        return Unmanaged.passUnretained(event)
    }

    /// Returns non-nil if the event should be swallowed (match found on closing colon).
    private func consume(_ scalar: UnicodeScalar, event: CGEvent) -> Unmanaged<CGEvent>?? {
        let character = Character(scalar)

        if character == ":" {
            typedBuffer.append(character)
            trimBufferIfNeeded()
            if let match = attemptMatch() {
                // Swallow the closing `:` and perform replacement.
                // We need to delete the characters already typed (the `:shortcode` part,
                // not including the closing `:` which we're swallowing).
                let charsToDelete = match.alias.count + 1  // alias + opening colon
                EmojiReplacer.replace(characterCount: charsToDelete, with: match.replacement)
                typedBuffer.removeAll(keepingCapacity: true)
                onReplacement?(match.alias, match.replacement)
                return .some(nil)  // swallow event
            }
            return nil  // don't swallow, no match
        }

        if scalar.properties.isWhitespace {
            typedBuffer.removeAll(keepingCapacity: true)
            return nil
        }

        if EmojiAliasMatcher.isAllowedAliasScalar(scalar) {
            typedBuffer.append(character)
            trimBufferIfNeeded()
            return nil
        }

        typedBuffer.removeAll(keepingCapacity: true)
        return nil
    }

    private func trimBufferIfNeeded() {
        guard typedBuffer.count > maxBufferSize else { return }
        typedBuffer.removeFirst(typedBuffer.count - maxBufferSize)
    }

    private func attemptMatch() -> EmojiAliasMatch? {
        EmojiAliasMatcher.bestMatch(in: typedBuffer, aliases: aliases)
    }

    // MARK: - Context filtering

    private func shouldProcessCurrentContext() -> Bool {
        guard !isFocusedElementSecureInput() else { return false }

        let currentBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?
            .lowercased()

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
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(systemWide, "AXFocusedUIElement" as CFString, &focusedRef) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return false }

        let element = focusedRef as! AXUIElement

        var protectedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXValueProtected" as CFString, &protectedValue) == .success,
           let isProtected = protectedValue as? Bool, isProtected
        {
            return true
        }

        var subroleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXSubrole" as CFString, &subroleValue) == .success,
           let subrole = subroleValue as? String, subrole == "AXSecureTextField"
        {
            return true
        }

        return false
    }
}

extension CGEvent {
    var unicodeText: String? {
        var characters = [UniChar](repeating: 0, count: 8)
        var count = 0
        keyboardGetUnicodeString(
            maxStringLength: characters.count,
            actualStringLength: &count,
            unicodeString: &characters)
        guard count > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: count)
    }
}
