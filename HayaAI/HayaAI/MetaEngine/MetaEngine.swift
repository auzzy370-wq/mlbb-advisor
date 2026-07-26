import Foundation

// MARK: - Meta Engine
actor MetaEngine: MetaEngineProtocol {

    private var patch: String = "1.8.72"
    private let heroDatabase: HeroDatabaseService

    init(heroDatabase: HeroDatabaseService) {
        self.heroDatabase = heroDatabase
    }

    func currentPatch() async -> String { patch }

    func metaScore(for hero: Hero) async -> Double {
        // Weighted combination of pro and rank data with ban priority
        let proWeight = hero.professionalPickRate * 10
        let winWeight = hero.professionalWinRate * 10
        let banWeight = hero.banPriority
        return (proWeight * 0.4 + winWeight * 0.3 + banWeight * 0.3)
    }

    func topMetaHeroes(limit: Int) async throws -> [Hero] {
        let heroes = await heroDatabase.heroes
        return heroes
            .sorted { $0.metaScore > $1.metaScore }
            .prefix(limit)
            .map { $0 }
    }

    func updateMeta(from data: Data) async throws {
        let decoder = JSONDecoder()
        let metaUpdate = try decoder.decode(MetaUpdate.self, from: data)
        patch = metaUpdate.patchVersion
        // Notify subscribers that meta has been updated
    }
}

// MARK: - Meta Update
private struct MetaUpdate: Codable {
    let patchVersion: String
    let changes: [HeroMetaChange]
}

private struct HeroMetaChange: Codable {
    let heroID: String
    let metaScore: Double
    let banPriority: Double
    let draftPriority: Double
    let notes: String?
}
