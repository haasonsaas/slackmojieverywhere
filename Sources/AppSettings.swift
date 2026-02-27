import Foundation

enum AppFilterMode: String, CaseIterable {
    case off
    case allowlist
    case denylist

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .allowlist:
            return "Allow List"
        case .denylist:
            return "Deny List"
        }
    }
}

@MainActor
final class AppSettingsStore {
    static let shared = AppSettingsStore()

    private enum Keys {
        static let launchAtLoginEnabled = "settings.launchAtLoginEnabled"
        static let appFilterMode = "settings.appFilterMode"
        static let appFilterBundleIDs = "settings.appFilterBundleIDs"
    }

    private let defaults = UserDefaults.standard

    private init() {}

    var launchAtLoginEnabled: Bool {
        get {
            defaults.bool(forKey: Keys.launchAtLoginEnabled)
        }
        set {
            defaults.set(newValue, forKey: Keys.launchAtLoginEnabled)
        }
    }

    var appFilterMode: AppFilterMode {
        get {
            guard let raw = defaults.string(forKey: Keys.appFilterMode),
                  let mode = AppFilterMode(rawValue: raw)
            else {
                return .off
            }

            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.appFilterMode)
        }
    }

    var appFilterBundleIDs: [String] {
        get {
            guard let values = defaults.array(forKey: Keys.appFilterBundleIDs) as? [String] else {
                return []
            }

            return normalizeBundleIDs(values)
        }
        set {
            defaults.set(normalizeBundleIDs(newValue), forKey: Keys.appFilterBundleIDs)
        }
    }

    func normalizeBundleIDs(_ bundleIDs: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for value in bundleIDs {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { continue }

            if seen.insert(trimmed).inserted {
                normalized.append(trimmed)
            }
        }

        return normalized
    }

    func parseBundleIDs(from text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",\n")
        let rawValues = text.components(separatedBy: separators)
        return normalizeBundleIDs(rawValues)
    }

    func bundleIDsText(from bundleIDs: [String]) -> String {
        normalizeBundleIDs(bundleIDs).joined(separator: "\n")
    }
}
