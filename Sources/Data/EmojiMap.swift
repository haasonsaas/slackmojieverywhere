import Foundation

@MainActor
final class EmojiMap: ObservableObject {
    @Published private(set) var aliases: [String: String] = [:]

    private static let customAliasesFolder = "SlackmojiEverywhere"
    private static let customAliasesFile = "custom_aliases.json"

    init() {
        reload()
    }

    func reload() {
        let bundled = loadBundledAliases()
        let custom = loadCustomAliases()
        aliases = bundled.merging(custom) { _, customValue in customValue }
    }

    func lookup(_ shortcode: String) -> String? {
        aliases[shortcode.lowercased()]
    }

    // MARK: - Bundled aliases

    private func loadBundledAliases() -> [String: String] {
        guard let url = Bundle.module.url(forResource: "slack_emoji_aliases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return Self.normalize(raw)
    }

    // MARK: - Custom aliases

    private func loadCustomAliases() -> [String: String] {
        guard let url = Self.customAliasesFileURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return Self.normalize(raw)
    }

    static func readCustomAliasesJSON() throws -> String {
        guard let url = ensureCustomAliasesFileExists() else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        let aliases = try JSONDecoder().decode([String: String].self, from: data)
        let normalized = normalize(aliases)
        let formatted = try JSONSerialization.data(
            withJSONObject: normalized, options: [.prettyPrinted, .sortedKeys])
        guard var json = String(data: formatted, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if !json.hasSuffix("\n") { json.append("\n") }
        return json
    }

    static func saveCustomAliasesJSON(_ jsonString: String) throws {
        guard let url = ensureCustomAliasesFileExists() else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard let inputData = jsonString.data(using: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let aliases = try JSONDecoder().decode([String: String].self, from: inputData)
        let normalized = normalize(aliases)
        var formatted = try JSONSerialization.data(
            withJSONObject: normalized, options: [.prettyPrinted, .sortedKeys])
        if formatted.last != 0x0A { formatted.append(0x0A) }
        try formatted.write(to: url, options: [.atomic])
    }

    @discardableResult
    static func ensureCustomAliasesFileExists() -> URL? {
        guard let url = customAliasesFileURL() else { return nil }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }

        let template: [String: String] = [
            "partyparrot": "🦜",
            "shipit": "🚢",
            "shruggie": "¯\\_(ツ)_/¯",
        ]
        if let data = try? JSONEncoder().encode(template) {
            try? data.write(to: url, options: [.atomic])
        }
        return url
    }

    static func customAliasesFileURL() -> URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }

        return appSupport
            .appendingPathComponent(customAliasesFolder, isDirectory: true)
            .appendingPathComponent(customAliasesFile, isDirectory: false)
    }

    private static func normalize(_ aliases: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(aliases.count)
        for (key, value) in aliases {
            let alias = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let replacement = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !alias.isEmpty, !replacement.isEmpty else { continue }
            result[alias] = replacement
        }
        return result
    }
}
