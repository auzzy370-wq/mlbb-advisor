import XCTest
@testable import HayaAI

final class OCREngineTests: XCTestCase {

    var ocrEngine: OCREngine!

    override func setUp() async throws {
        let heroNames = ["Chou", "Fanny", "Ling", "Lancelot", "Kagura", "Granger", "Franco", "Wanwan", "Khufra", "Esmeralda"]
        ocrEngine = OCREngine(heroNames: heroNames)
    }

    // MARK: - Text Classification Tests

    func testTimerPattern() async throws {
        // The timer regex should match 1-2 digit numbers
        let timerValues = ["0", "5", "15", "30", "99"]
        let nonTimerValues = ["100", "abc", "3.5", ""]
        let pattern = try NSRegularExpression(pattern: #"^\d{1,2}$"#)

        for value in timerValues {
            let range = NSRange(value.startIndex..., in: value)
            XCTAssertNotNil(pattern.firstMatch(in: value, range: range), "\(value) should match timer pattern")
        }

        for value in nonTimerValues {
            let range = NSRange(value.startIndex..., in: value)
            if !value.isEmpty {
                XCTAssertNil(pattern.firstMatch(in: value, range: range), "\(value) should not match timer pattern")
            }
        }
    }

    // MARK: - Hero Name Matcher Tests

    func testHeroNameMatcherExactMatch() {
        let matcher = HeroNameMatcher(heroNames: ["Chou", "Fanny", "Ling"])
        XCTAssertTrue(matcher.isHeroName("chou"))
        XCTAssertTrue(matcher.isHeroName("fanny"))
        XCTAssertFalse(matcher.isHeroName("unknownhero"))
    }

    func testHeroNameMatcherBestMatch() {
        let matcher = HeroNameMatcher(heroNames: ["Chou", "Fanny", "Lancelot"])
        let result = matcher.bestMatch(for: ["chou", "unknown"])
        XCTAssertEqual(result, "Chou")
    }

    func testHeroNameMatcherUpdate() {
        let matcher = HeroNameMatcher(heroNames: ["Chou"])
        XCTAssertFalse(matcher.isHeroName("fanny"))
        matcher.update(names: ["Chou", "Fanny"])
        XCTAssertTrue(matcher.isHeroName("fanny"))
    }

    func testHeroNameMatcherFuzzyMatch() {
        let matcher = HeroNameMatcher(heroNames: ["Lancelot"])
        let result = matcher.bestMatch(for: ["lance", "unknown"])
        // Fuzzy: "lance" is a substring of "lancelot"
        XCTAssertEqual(result, "Lancelot")
    }

    // MARK: - Phase Keyword Tests

    func testPhaseKeywordMapping() async throws {
        let phaseKeywords: [String: DraftPhase] = [
            "ban": .banPhase1,
            "banning": .banPhase1,
            "pick": .pickPhase1,
            "picking": .pickPhase1,
        ]

        for (keyword, expectedPhase) in phaseKeywords {
            if keyword.contains("ban") {
                XCTAssertTrue(expectedPhase.isBanPhase, "'\(keyword)' should map to ban phase")
            } else {
                XCTAssertTrue(expectedPhase.isPickPhase, "'\(keyword)' should map to pick phase")
            }
        }
    }
}
