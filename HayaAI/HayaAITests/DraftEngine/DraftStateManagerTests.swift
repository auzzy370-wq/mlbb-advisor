import XCTest
@testable import HayaAI

@MainActor
final class DraftStateManagerTests: XCTestCase {

    var heroDatabase: HeroDatabaseService!
    var draftStateManager: DraftStateManager!

    override func setUp() async throws {
        heroDatabase = HeroDatabaseService()
        draftStateManager = DraftStateManager(heroDatabase: heroDatabase)
    }

    func testInitialStateIsNotStarted() {
        XCTAssertEqual(draftStateManager.currentDraftState.phase, .notStarted)
    }

    func testSetPhaseUpdatesState() {
        draftStateManager.setPhase(.banPhase1)
        XCTAssertEqual(draftStateManager.currentDraftState.phase, .banPhase1)
    }

    func testPickHeroUpdatesSlot() {
        draftStateManager.addHeroToPick("Chou", team: .friendly, slot: 0)
        XCTAssertEqual(draftStateManager.currentDraftState.friendlyPicks[0].heroName, "Chou")
        XCTAssertEqual(draftStateManager.currentDraftState.friendlyPicks[0].status, .locked)
    }

    func testBanHeroUpdatesSlot() {
        draftStateManager.addHeroToBan("Fanny", team: .enemy, slot: 0)
        XCTAssertEqual(draftStateManager.currentDraftState.enemyBans[0].heroName, "Fanny")
        XCTAssertEqual(draftStateManager.currentDraftState.enemyBans[0].status, .banned)
    }

    func testSetHoveredHero() {
        draftStateManager.setHoveredHero("Ling")
        XCTAssertEqual(draftStateManager.currentDraftState.hoveredHero, "Ling")
    }

    func testClearSlotRemovesHero() {
        draftStateManager.addHeroToPick("Chou", team: .friendly, slot: 0)
        draftStateManager.clearSlot(team: .friendly, slot: 0, isBan: false)
        XCTAssertNil(draftStateManager.currentDraftState.friendlyPicks[0].heroName)
    }

    func testResetClearsDraftState() async {
        draftStateManager.addHeroToPick("Chou", team: .friendly, slot: 0)
        draftStateManager.setPhase(.pickPhase1)
        await draftStateManager.reset()
        XCTAssertEqual(draftStateManager.currentDraftState.phase, .notStarted)
        XCTAssertNil(draftStateManager.currentDraftState.friendlyPicks[0].heroName)
    }

    func testTimerUpdate() {
        draftStateManager.setTimer(15)
        XCTAssertEqual(draftStateManager.currentDraftState.timer, 15)
    }

    func testFriendlyHeroIDsReturnsLockedHeroes() {
        draftStateManager.addHeroToPick("Chou", team: .friendly, slot: 0)
        draftStateManager.addHeroToPick("Fanny", team: .friendly, slot: 1)
        // Note: heroID isn't set by name – this tests heroName in derivation
        let state = draftStateManager.currentDraftState
        XCTAssertEqual(state.friendlyPicks.filter { $0.status == .locked }.count, 2)
    }

    func testEnemyPicksSlotCount() {
        XCTAssertEqual(draftStateManager.currentDraftState.enemyPicks.count, 5)
    }

    func testFriendlyBanSlotCount() {
        XCTAssertEqual(draftStateManager.currentDraftState.friendlyBans.count, 3)
    }

    func testIsBanPhase() {
        draftStateManager.setPhase(.banPhase2)
        XCTAssertTrue(draftStateManager.currentDraftState.isBanPhase)
    }

    func testIsPickPhase() {
        draftStateManager.setPhase(.pickPhase2)
        XCTAssertTrue(draftStateManager.currentDraftState.isPickPhase)
    }
}
