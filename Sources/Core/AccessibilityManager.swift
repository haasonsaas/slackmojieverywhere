import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class AccessibilityManager: ObservableObject {
    @Published private(set) var isTrusted: Bool = false

    private var pollTimer: Timer?

    init() {
        isTrusted = AXIsProcessTrusted()
    }

    func promptIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
        if !isTrusted {
            startPolling()
        }
    }

    func recheckPermission() {
        isTrusted = AXIsProcessTrusted()
        if isTrusted {
            stopPolling()
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recheckPermission()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
