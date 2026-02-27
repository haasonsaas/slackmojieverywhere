public struct EmojiAliasMatch: Equatable {
    public let alias: String
    public let replacement: String

    public init(alias: String, replacement: String) {
        self.alias = alias
        self.replacement = replacement
    }
}

public enum EmojiAliasMatcher {
    public static func bestMatch(in typedBuffer: String, aliases: [String: String], maxAliasLength: Int = 80) -> EmojiAliasMatch? {
        guard typedBuffer.last == ":" else { return nil }

        let withoutClosingColon = typedBuffer.dropLast()
        var bestMatch: EmojiAliasMatch?

        var index = withoutClosingColon.startIndex
        while index < withoutClosingColon.endIndex {
            defer { index = withoutClosingColon.index(after: index) }

            guard withoutClosingColon[index] == ":" else { continue }

            let aliasStart = withoutClosingColon.index(after: index)
            let alias = String(withoutClosingColon[aliasStart...]).lowercased()

            guard !alias.isEmpty, alias.count <= maxAliasLength else { continue }
            guard isValidAlias(alias) else { continue }
            guard let replacement = aliases[alias] else { continue }

            if bestMatch == nil || alias.count > bestMatch!.alias.count {
                bestMatch = EmojiAliasMatch(alias: alias, replacement: replacement)
            }
        }

        return bestMatch
    }

    public static func isAllowedAliasScalar(_ scalar: UnicodeScalar) -> Bool {
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

    public static func isValidAlias(_ alias: String) -> Bool {
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
