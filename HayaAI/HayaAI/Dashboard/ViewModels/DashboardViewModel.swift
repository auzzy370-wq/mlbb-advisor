import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var topMetaHeroes: [Hero] = []
    @Published private(set) var recentRecommendations: [HeroRecommendation] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var currentPatch: String = "1.8.72"

    private let heroDatabase: HeroDatabaseService
    private let metaEngine: MetaEngine

    init(heroDatabase: HeroDatabaseService) {
        self.heroDatabase = heroDatabase
        self.metaEngine = MetaEngine(heroDatabase: heroDatabase)
        Task { await loadData() }
    }

    private func loadData() async {
        isLoading = true
        currentPatch = await metaEngine.currentPatch()
        topMetaHeroes = (try? await metaEngine.topMetaHeroes(limit: 10)) ?? []
        isLoading = false
    }
}
