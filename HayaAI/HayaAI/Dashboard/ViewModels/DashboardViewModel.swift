import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var topMetaHeroes: [Hero] = []
    @Published private(set) var recentRecommendations: [HeroRecommendation] = []
    @Published private(set) var isLoading: Bool = false

    private let heroDatabase: HeroDatabaseService
    private let metaEngine: MetaEngine
    private var cancellables = Set<AnyCancellable>()

    init(heroDatabase: HeroDatabaseService) {
        self.heroDatabase = heroDatabase
        self.metaEngine = MetaEngine(heroDatabase: heroDatabase)

        // Reload the top meta list whenever the hero database changes
        // (covers both initial load and auto-updates from GitHub).
        heroDatabase.$heroes
            .filter { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.loadData() }
            }
            .store(in: &cancellables)

        if heroDatabase.isLoaded {
            Task { await loadData() }
        }
    }

    private func loadData() async {
        isLoading = true
        topMetaHeroes = (try? await metaEngine.topMetaHeroes(limit: 9)) ?? []
        isLoading = false
    }
}
