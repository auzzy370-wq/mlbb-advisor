import XCTest
@testable import HayaAI

@MainActor
final class RecommendationEngineTests: XCTestCase {

    var heroDatabase: HeroDatabaseService!
    var engine: RecommendationEngine!

    override func setUp() async throws {
        heroDatabase = HeroDatabaseService()
        // Wait for initial load
        try await Task.sleep(nanoseconds: 100_000_000)
        engine = RecommendationEngine(heroDatabase: heroDatabase)
    }

    // MARK: - Score Computation Tests

    func testOverallScoreWithinRange() async throws {
        let heroes = MockHeroFactory.sampleHeroes()
        guard let hero = heroes.first else { XCTFail("No hero"); return }

        var scores = HeroScoreComponents()
        scores.counterScore = 7.0
        scores.synergyScore = 8.0
        scores.laneScore = 6.0
        scores.metaScore = 7.5
        scores.scalingScore = 8.0
        scores.comfortScore = 5.0
        scores.difficultyScore = 6.0
        scores.executionScore = 5.0
        scores.computeOverall()

        XCTAssertGreaterThanOrEqual(scores.overallScore, 0.0)
        XCTAssertLessThanOrEqual(scores.overallScore, 10.0)
        XCTAssertGreaterThanOrEqual(scores.confidence, 0.0)
        XCTAssertLessThanOrEqual(scores.confidence, 1.0)
    }

    func testWeightsSumToOne() {
        let w = HeroScoreComponents.weights
        let sum = w.counter + w.synergy + w.lane + w.meta + w.scaling + w.comfort + w.difficulty + w.execution
        XCTAssertEqual(sum, 1.0, accuracy: 0.0001)
    }

    func testConfidenceIsProportionalToOverallScore() {
        var scores = HeroScoreComponents()
        scores.counterScore = 8
        scores.synergyScore = 8
        scores.laneScore = 8
        scores.metaScore = 8
        scores.scalingScore = 8
        scores.comfortScore = 8
        scores.difficultyScore = 8
        scores.executionScore = 8
        scores.computeOverall()

        XCTAssertEqual(scores.confidence, scores.overallScore / 10.0, accuracy: 0.0001)
    }

    // MARK: - Recommendation Tests

    func testRecommendationsReturnTopFive() async throws {
        var draftState = DraftState()
        draftState.phase = .pickPhase1

        let result = try await engine.generateRecommendations(
            for: draftState,
            userProfile: nil,
            limit: 5
        )

        XCTAssertLessThanOrEqual(result.recommendations.count, 5)
    }

    func testRecommendationsExcludePickedHeroes() async throws {
        var draftState = DraftState()
        draftState.friendlyPicks[0].heroName = "Chou"
        draftState.friendlyPicks[0].status = .locked

        let result = try await engine.generateRecommendations(
            for: draftState,
            userProfile: nil,
            limit: 5
        )

        let names = result.recommendations.map { $0.hero.name }
        XCTAssertFalse(names.contains("Chou"))
    }

    func testRecommendationsExcludeBannedHeroes() async throws {
        var draftState = DraftState()
        draftState.enemyBans[0].heroName = "Fanny"
        draftState.enemyBans[0].status = .banned

        let result = try await engine.generateRecommendations(
            for: draftState,
            userProfile: nil,
            limit: 5
        )

        let names = result.recommendations.map { $0.hero.name }
        XCTAssertFalse(names.contains("Fanny"))
    }

    func testRecommendationsAreSortedByScore() async throws {
        let result = try await engine.generateRecommendations(
            for: DraftState(),
            userProfile: nil,
            limit: 5
        )

        let scores = result.recommendations.map { $0.scores.overallScore }
        for i in 0..<(scores.count - 1) {
            XCTAssertGreaterThanOrEqual(scores[i], scores[i + 1])
        }
    }

    func testTopPickMatchesFirstRecommendation() async throws {
        let result = try await engine.generateRecommendations(
            for: DraftState(),
            userProfile: nil,
            limit: 5
        )

        if let top = result.topPick, let first = result.recommendations.first {
            XCTAssertEqual(top.id, first.id)
        }
    }
}
