import Foundation
@testable import HayaAI

final class MockHeroDatabaseService: @unchecked Sendable {
    var heroes: [Hero] = MockHeroFactory.sampleHeroes()
    var isLoaded = true
    var currentPatch = "1.8.72"

    func hero(byID id: String) async -> Hero? { heroes.first { $0.id == id } }
    func hero(byName name: String) async -> Hero? { heroes.first { $0.name == name } }
    func hero(byNameFuzzy name: String) async -> Hero? {
        heroes.first { $0.name.lowercased().contains(name.lowercased()) }
    }
    func heroes(forRole role: HeroRole) async -> [Hero] { heroes.filter { $0.primaryRole == role } }
    func heroes(forLane lane: HeroLane) async -> [Hero] { heroes.filter { $0.primaryLane == lane } }
    func allHeroNames() async -> [String] { heroes.map { $0.name } }
}
