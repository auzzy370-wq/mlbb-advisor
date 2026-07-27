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
    private var cancellables = Set<AnyCancellable>()

    init(heroDatabase: HeroDatabaseService) {
        self.heroDatabase = heroDatabase
        self.metaEngine = MetaEngine(heroDatabase: heroDatabase)

        // Re-load dashboard data whenever the database finishes loading heroes.
        // This handles the async race between init() and the database Task.
        heroDatabase.$isLoaded
            .filter { $0 }
            .first()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { await self?.loadData() }
            }
            .store(in: &cancellables)

        // If heroes are already loaded (e.g. second instantiation), load immediately.
        if heroDatabase.isLoaded {
            Task { await loadData() }
        }
    }

    private func loadData() async {
        isLoading = true
        currentPatch = await metaEngine.currentPatch()
        topMetaHeroes = (try? await metaEngine.topMetaHeroes(limit: 10)) ?? []
        isLoading = false
    }
}
