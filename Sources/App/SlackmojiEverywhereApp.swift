import SwiftUI

@main
struct SlackmojiEverywhereApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            MenuBarLabel(appState: appState)
        }
    }

    init() {}
}

private struct MenuBarLabel: View {
    @ObservedObject var appState: AppState
    @State private var flashEmoji: String?

    var body: some View {
        Text(displayText)
            .onAppear {
                appState.setup()
            }
            .onReceive(appState.$recentReplacements) { replacements in
                guard let latest = replacements.first else { return }
                flashEmoji = latest.emoji
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if flashEmoji == latest.emoji {
                        flashEmoji = nil
                    }
                }
            }
    }

    private var displayText: String {
        if let flash = flashEmoji {
            return flash
        }
        if !appState.accessibilityManager.isTrusted {
            return "⚠️"
        }
        return appState.isEnabled ? "😄" : "😴"
    }
}
