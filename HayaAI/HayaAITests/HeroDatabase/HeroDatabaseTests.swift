import XCTest
@testable import HayaAI

@MainActor
final class HeroDatabaseTests: XCTestCase {

    var service: HeroDatabaseService!

    override func setUp() async throws {
        service = HeroDatabaseService()
        try await Task.sleep(nanoseconds: 200_000_000) // Wait for bundle load
    }

    func testHeroesLoadedFromBundle() async throws {
        _ = try await service.loadHeroes()
        XCTAssertFalse(service.heroes.isEmpty)
    }

    func testHeroByNameReturnsCorrectHero() async throws {
        _ = try await service.loadHeroes()
        let hero = await service.hero(byName: "Chou")
        XCTAssertNotNil(hero)
        XCTAssertEqual(hero?.id, "chou")
    }

    func testHeroByIDReturnsCorrectHero() async throws {
        _ = try await service.loadHeroes()
        let hero = await service.hero(byID: "fanny")
        XCTAssertNotNil(hero)
        XCTAssertEqual(hero?.name, "Fanny")
    }

    func testSearchHeroesFindsPartialMatch() async throws {
        _ = try await service.loadHeroes()
        let results = await service.searchHeroes(query: "ch")
        XCTAssertTrue(results.contains { $0.name == "Chou" })
    }

    func testHeroesForRoleFiltersCorrectly() async throws {
        _ = try await service.loadHeroes()
        let tanks = await service.heroes(forRole: .tank)
        XCTAssertTrue(tanks.allSatisfy { $0.primaryRole == .tank || $0.secondaryRole == .tank })
    }

    func testAllHeroNamesNonEmpty() async throws {
        _ = try await service.loadHeroes()
        let names = await service.allHeroNames()
        XCTAssertFalse(names.isEmpty)
    }

    func testPatchVersionLoaded() async throws {
        _ = try await service.loadHeroes()
        XCTAssertFalse(service.currentPatch.isEmpty)
        XCTAssertNotEqual(service.currentPatch, "unknown")
    }

    func testHeroHasRequiredFields() async throws {
        _ = try await service.loadHeroes()
        guard let hero = await service.hero(byName: "Ling") else {
            XCTFail("Ling not found")
            return
        }
        XCTAssertFalse(hero.id.isEmpty)
        XCTAssertFalse(hero.name.isEmpty)
        XCTAssertGreaterThan(hero.metaScore, 0)
        XCTAssertGreaterThan(hero.draftPriority, 0)
    }

    func testDraftStateUnavailableHeroes() {
        var state = DraftState()
        state.friendlyPicks[0].heroName = "Chou"
        state.friendlyBans[0].heroName = "Fanny"
        let unavailable = state.unavailableHeroIDs
        XCTAssertTrue(unavailable.contains("Chou"))
        XCTAssertTrue(unavailable.contains("Fanny"))
    }
}
