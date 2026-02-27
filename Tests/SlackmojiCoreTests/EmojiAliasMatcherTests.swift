import XCTest
@testable import SlackmojiCore

final class EmojiAliasMatcherTests: XCTestCase {
    func testFindsSimpleAliasMatch() {
        let aliases = ["smile": "😄"]

        let match = EmojiAliasMatcher.bestMatch(in: ":smile:", aliases: aliases)

        XCTAssertEqual(match, EmojiAliasMatch(alias: "smile", replacement: "😄"))
    }

    func testMatchingIsCaseInsensitive() {
        let aliases = ["rocket": "🚀"]

        let match = EmojiAliasMatcher.bestMatch(in: ":ROCKET:", aliases: aliases)

        XCTAssertEqual(match, EmojiAliasMatch(alias: "rocket", replacement: "🚀"))
    }

    func testReturnsNilWithoutClosingColon() {
        let aliases = ["smile": "😄"]

        let match = EmojiAliasMatcher.bestMatch(in: ":smile", aliases: aliases)

        XCTAssertNil(match)
    }

    func testChoosesLongestAliasWhenMultipleMatch() {
        let aliases = [
            "woman-cartwheeling": "🤸‍♀️",
            "woman-cartwheeling::skin-tone-5": "🤸🏾‍♀️"
        ]

        let match = EmojiAliasMatcher.bestMatch(in: "Hello :woman-cartwheeling::skin-tone-5:", aliases: aliases)

        XCTAssertEqual(match, EmojiAliasMatch(alias: "woman-cartwheeling::skin-tone-5", replacement: "🤸🏾‍♀️"))
    }

    func testRejectsInvalidSingleColonInAlias() {
        let aliases = ["foo:bar": "❌"]

        let match = EmojiAliasMatcher.bestMatch(in: ":foo:bar:", aliases: aliases)

        XCTAssertNil(match)
    }

    func testAllowsDoubleColonAliasSegments() {
        let aliases = ["foo::bar": "✅"]

        let match = EmojiAliasMatcher.bestMatch(in: ":foo::bar:", aliases: aliases)

        XCTAssertEqual(match, EmojiAliasMatch(alias: "foo::bar", replacement: "✅"))
    }

    func testAllowedAliasScalarRules() {
        XCTAssertTrue(EmojiAliasMatcher.isAllowedAliasScalar("a"))
        XCTAssertTrue(EmojiAliasMatcher.isAllowedAliasScalar("Z"))
        XCTAssertTrue(EmojiAliasMatcher.isAllowedAliasScalar("9"))
        XCTAssertTrue(EmojiAliasMatcher.isAllowedAliasScalar("+"))
        XCTAssertTrue(EmojiAliasMatcher.isAllowedAliasScalar("-"))
        XCTAssertTrue(EmojiAliasMatcher.isAllowedAliasScalar("_"))
        XCTAssertFalse(EmojiAliasMatcher.isAllowedAliasScalar(":"))
        XCTAssertFalse(EmojiAliasMatcher.isAllowedAliasScalar("🙂"))
    }
}
