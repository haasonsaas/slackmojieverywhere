import XCTest
@testable import SlackmojiCore

final class EmojiAliasMatcherEdgeCaseTests: XCTestCase {
    func testRejectsAliasOverMaxLength() {
        let longAlias = String(repeating: "a", count: 81)
        let aliases = [longAlias: "😀"]

        let match = EmojiAliasMatcher.bestMatch(in: ":\(longAlias):", aliases: aliases)

        XCTAssertNil(match)
    }

    func testAllowsAliasAtEndOfLongBuffer() {
        let aliases = ["shipit": "🚢"]

        let match = EmojiAliasMatcher.bestMatch(in: "some earlier text :shipit:", aliases: aliases)

        XCTAssertEqual(match?.alias, "shipit")
        XCTAssertEqual(match?.replacement, "🚢")
    }

    func testReturnsNilForUnknownAlias() {
        let aliases = ["known": "✅"]

        let match = EmojiAliasMatcher.bestMatch(in: ":unknown:", aliases: aliases)

        XCTAssertNil(match)
    }

    func testRejectsAliasWithSpaces() {
        let aliases = ["party parrot": "🦜"]

        let match = EmojiAliasMatcher.bestMatch(in: ":party parrot:", aliases: aliases)

        XCTAssertNil(match)
    }

    func testFindsBestMatchWhenSeveralColonsAppear() {
        let aliases = [
            "wave": "👋",
            "wave::skin-tone-2": "👋🏻"
        ]

        let match = EmojiAliasMatcher.bestMatch(in: "prefix:noise :wave::skin-tone-2:", aliases: aliases)

        XCTAssertEqual(match?.alias, "wave::skin-tone-2")
        XCTAssertEqual(match?.replacement, "👋🏻")
    }
}
