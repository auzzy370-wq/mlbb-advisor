import Foundation

// MARK: - Recommendation Engine Protocol
protocol RecommendationEngineProtocol: AnyObject, Sendable {
    func generateRecommendations(
        for draftState: DraftState,
        userProfile: UserProfile?,
        limit: Int
    ) async throws -> RecommendationResult

    func scoreHero(
        _ hero: Hero,
        draftState: DraftState,
        userProfile: UserProfile?
    ) async throws -> HeroScoreComponents

    func analyzeTeamComposition(
        heroIDs: [String],
        team: DraftTurn
    ) async throws -> TeamCompositionAnalysis
}

// MARK: - Draft Engine Protocol
protocol DraftEngineProtocol: AnyObject, Sendable {
    var currentDraftState: DraftState { get }
    var statePublisher: AsyncStream<DraftState> { get }

    func update(with analysisResult: FrameAnalysisResult) async
    func reset() async
    func setPhase(_ phase: DraftPhase) async
    func addHeroToPick(_ heroName: String, team: DraftTurn, slot: Int) async
    func addHeroToBan(_ heroName: String, team: DraftTurn, slot: Int) async
    func setHoveredHero(_ heroName: String?) async
    func setTimer(_ seconds: Int) async
}

// MARK: - Hero Database Protocol
protocol HeroDatabaseProtocol: AnyObject, Sendable {
    func loadHeroes() async throws -> [Hero]
    func hero(byID id: String) async throws -> Hero?
    func hero(byName name: String) async throws -> Hero?
    func heroes(forRole role: HeroRole) async throws -> [Hero]
    func heroes(forLane lane: HeroLane) async throws -> [Hero]
    func searchHeroes(query: String) async throws -> [Hero]
    func allHeroNames() async -> [String]
}

// MARK: - Item Engine Protocol
protocol ItemEngineProtocol: AnyObject, Sendable {
    func recommendBuild(
        for hero: Hero,
        against enemyHeroes: [Hero],
        situation: BuildSituation
    ) async throws -> SuggestedBuild

    func counterBuildItems(
        against enemyHeroes: [Hero]
    ) async throws -> [Item]
}

enum BuildSituation: String, Sendable {
    case standard = "Standard"
    case snowball = "Snowball"
    case comeback = "Comeback"
    case lateGame = "Late Game"
    case antiHeal = "Anti Heal"
}

// MARK: - Strategy Engine Protocol
protocol StrategyEngineProtocol: AnyObject, Sendable {
    func generateStrategy(
        friendlyHeroes: [Hero],
        enemyHeroes: [Hero],
        draftState: DraftState
    ) async throws -> DraftStrategy
}

// MARK: - Meta Engine Protocol
protocol MetaEngineProtocol: AnyObject, Sendable {
    func currentPatch() async -> String
    func metaScore(for hero: Hero) async -> Double
    func topMetaHeroes(limit: Int) async throws -> [Hero]
    func updateMeta(from data: Data) async throws
}

// MARK: - Authentication Service Protocol
protocol AuthenticationServiceProtocol: AnyObject, Sendable {
    var isAuthenticated: Bool { get }
    var currentUserID: String? { get }

    func signIn(email: String, password: String) async throws -> UserProfile
    func signUp(email: String, password: String, displayName: String) async throws -> UserProfile
    func signOut() async throws
    func currentUser() async throws -> UserProfile?
    func updateProfile(_ profile: UserProfile) async throws
}

// MARK: - Analytics Service Protocol
protocol AnalyticsServiceProtocol: AnyObject, Sendable {
    func track(event: AnalyticsEvent) async
    func track(screen: String) async
    func setUserProperty(key: String, value: String) async
}

struct AnalyticsEvent: Sendable {
    let name: String
    let parameters: [String: String]
}

// MARK: - ReplayKit Manager Protocol
protocol ReplayKitManagerProtocol: AnyObject, Sendable {
    var isCapturing: Bool { get }
    var onFrameCaptured: ((CVPixelBufferRef, CMTimeValue) -> Void)? { get set }

    func startCapture() async throws
    func stopCapture() async
    func requestPermission() async throws -> Bool
}
