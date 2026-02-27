import AppKit
import Carbon.HIToolbox
import Foundation

enum EmojiReplacer {
    private static let injectedEventMarker: Int64 = 0x534D4A59

    static func replace(characterCount: Int, with emoji: String) {
        guard characterCount > 0 else { return }

        for _ in 0..<characterCount {
            postKey(keyCode: CGKeyCode(kVK_Delete))
        }

        pasteText(emoji)
    }

    private static func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.pasteboardItems?.compactMap { item -> (NSPasteboard.PasteboardType, Data)? in
            guard let type = item.types.first, let data = item.data(forType: type) else { return nil }
            return (type, data)
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        postCommandV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pasteboard.clearContents()
            if let previousContents, !previousContents.isEmpty {
                for (type, data) in previousContents {
                    pasteboard.setData(data, forType: type)
                }
            }
        }
    }

    private static func postCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let vKeyCode = CGKeyCode(kVK_ANSI_V)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.setIntegerValueField(.eventSourceUserData, value: injectedEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: injectedEventMarker)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private static func postKey(keyCode: CGKeyCode) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }

        keyDown.setIntegerValueField(.eventSourceUserData, value: injectedEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: injectedEventMarker)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
