import Combine
import Foundation
import ServiceManagement

struct RecentReplacement: Identifiable {
    let id = UUID()
    let alias: String
    let emoji: String
    let date: Date
}

@MainActor
final class AppState: ObservableObject {
    @Published var isEnabled: Bool = true {
        didSet { isEnabled ? startMonitoring() : stopMonitoring() }
    }

    @Published private(set) var recentReplacements: [RecentReplacement] = []
    @Published var launchAtLogin: Bool = false {
        didSet { updateLaunchAtLogin() }
    }
    @Published var appFilterMode: AppFilterMode = .off {
        didSet { applyFilterSettings() }
    }
    @Published var appFilterBundleIDs: [String] = [] {
        didSet { applyFilterSettings() }
    }

    let accessibilityManager = AccessibilityManager()
    let emojiMap = EmojiMap()
    let keyboardMonitor = KeyboardMonitor()

    private let settingsStore = AppSettingsStore.shared
    private var cancellables = Set<AnyCancellable>()
    private let maxRecentReplacements = 8

    init() {
        loadSettings()
        setupBindings()
    }

    func setup() {
        _ = EmojiMap.ensureCustomAliasesFileExists()
        emojiMap.reload()
        keyboardMonitor.updateAliases(emojiMap.aliases)

        accessibilityManager.promptIfNeeded()

        keyboardMonitor.onReplacement = { [weak self] alias, emoji in
            Task { @MainActor in
                self?.addRecentReplacement(alias: alias, emoji: emoji)
            }
        }

        if accessibilityManager.isTrusted {
            startMonitoring()
        }
    }

    func reloadAliases() {
        emojiMap.reload()
        keyboardMonitor.updateAliases(emojiMap.aliases)
    }

    // MARK: - Private

    private func loadSettings() {
        launchAtLogin = settingsStore.launchAtLoginEnabled
        appFilterMode = settingsStore.appFilterMode
        appFilterBundleIDs = settingsStore.appFilterBundleIDs
    }

    private func setupBindings() {
        accessibilityManager.$isTrusted
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] trusted in
                guard let self, trusted, self.isEnabled else { return }
                self.startMonitoring()
            }
            .store(in: &cancellables)

        emojiMap.$aliases
            .receive(on: DispatchQueue.main)
            .sink { [weak self] aliases in
                self?.keyboardMonitor.updateAliases(aliases)
            }
            .store(in: &cancellables)
    }

    private func startMonitoring() {
        guard isEnabled, accessibilityManager.isTrusted else { return }
        _ = keyboardMonitor.start()
    }

    private func stopMonitoring() {
        keyboardMonitor.stop()
    }

    private func addRecentReplacement(alias: String, emoji: String) {
        let replacement = RecentReplacement(alias: alias, emoji: emoji, date: Date())
        recentReplacements.insert(replacement, at: 0)
        if recentReplacements.count > maxRecentReplacements {
            recentReplacements.removeLast()
        }
    }

    private func updateLaunchAtLogin() {
        settingsStore.launchAtLoginEnabled = launchAtLogin
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently handle - the toggle state is already saved in UserDefaults.
        }
    }

    private func applyFilterSettings() {
        settingsStore.appFilterMode = appFilterMode
        settingsStore.appFilterBundleIDs = appFilterBundleIDs
        keyboardMonitor.updateFiltering(mode: appFilterMode, bundleIDs: appFilterBundleIDs)
    }
}
