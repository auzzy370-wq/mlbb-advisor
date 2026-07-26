import Foundation

// MARK: - Score Components
struct HeroScoreComponents: Codable, Sendable {
    var counterScore: Double = 0
    var synergyScore: Double = 0
    var laneScore: Double = 0
    var metaScore: Double = 0
    var scalingScore: Double = 0
    var comfortScore: Double = 0
    var difficultyScore: Double = 0
    var executionScore: Double = 0
    var overallScore: Double = 0
    var confidence: Double = 0

    static let weights = ScoreWeights(
        counter: 0.20,
        synergy: 0.20,
        lane: 0.15,
        meta: 0.15,
        scaling: 0.10,
        comfort: 0.10,
        difficulty: 0.05,
        execution: 0.05
    )

    mutating func computeOverall() {
        let w = HeroScoreComponents.weights
        overallScore = (counterScore * w.counter)
            + (synergyScore * w.synergy)
            + (laneScore * w.lane)
            + (metaScore * w.meta)
            + (scalingScore * w.scaling)
            + (comfortScore * w.comfort)
            + (difficultyScore * w.difficulty)
            + (executionScore * w.execution)
        overallScore = min(10.0, max(0.0, overallScore))
        confidence = overallScore / 10.0
    }
}

struct ScoreWeights: Codable, Sendable {
    let counter: Double
    let synergy: Double
    let lane: Double
    let meta: Double
    let scaling: Double
    let comfort: Double
    let difficulty: Double
    let execution: Double
}

// MARK: - Suggested Build
struct SuggestedBuild: Codable, Sendable {
    var coreItems: [Item] = []
    var situationalItems: [Item] = []
    var counterItems: [Item] = []
    var boots: Item?
    var buildExplanation: String = ""
}

// MARK: - Hero Recommendation
struct HeroRecommendation: Codable, Identifiable, Sendable {
    let id: String
    let hero: Hero
    var scores: HeroScoreComponents
    var rank: Int = 0
    var reason: String = ""
    var advantages: [String] = []
    var weaknesses: [String] = []
    var suggestedBuild: SuggestedBuild = SuggestedBuild()
    var suggestedSpell: BattleSpell
    var suggestedEmblem: EmblemType
    var suggestedTalent: Talent?
    var laneAssignment: HeroLane?
    var strategyNote: String = ""
    var generatedAt: Date = Date()

    init(hero: Hero, scores: HeroScoreComponents) {
        self.id = UUID().uuidString
        self.hero = hero
        self.scores = scores
        self.suggestedSpell = hero.bestSpell
        self.suggestedEmblem = hero.bestEmblem
        self.suggestedTalent = hero.talents.first
    }
}

// MARK: - Recommendation Result
struct RecommendationResult: Sendable {
    let recommendations: [HeroRecommendation]
    let topPick: HeroRecommendation?
    let draftState: DraftState
    let teamAnalysis: TeamCompositionAnalysis
    let generatedAt: Date

    init(recommendations: [HeroRecommendation], draftState: DraftState, teamAnalysis: TeamCompositionAnalysis) {
        self.recommendations = recommendations.sorted { $0.scores.overallScore > $1.scores.overallScore }
        self.topPick = self.recommendations.first
        self.draftState = draftState
        self.teamAnalysis = teamAnalysis
        self.generatedAt = Date()
    }
}
