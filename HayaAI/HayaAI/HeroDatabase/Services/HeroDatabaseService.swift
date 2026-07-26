import Foundation
import Combine

// MARK: - Hero Database Service
/// Loads, caches, and queries the hero JSON database.
/// Supports versioned patch data loaded from local bundle or remote.
@MainActor
final class HeroDatabaseService: ObservableObject, HeroDatabaseProtocol {

    @Published private(set) var heroes: [Hero] = []
    @Published private(set) var isLoaded: Bool = false
    @Published private(set) var currentPatch: String = "unknown"
    @Published private(set) var loadError: Error? = nil

    private var heroByID: [String: Hero] = [:]
    private var heroByName: [String: Hero] = [:]
    private var heroByRole: [HeroRole: [Hero]] = [:]
    private var heroByLane: [HeroLane: [Hero]] = [:]

    nonisolated let networkService: NetworkService

    init(networkService: NetworkService = NetworkService()) {
        self.networkService = networkService
        Task { try? await loadHeroes() }
    }

    // MARK: - HeroDatabaseProtocol

    func loadHeroes() async throws -> [Hero] {
        do {
            let loaded = try await loadFromBundle()
            applyHeroes(loaded)
            isLoaded = true
            return loaded
        } catch {
            loadError = error
            throw error
        }
    }

    func hero(byID id: String) async -> Hero? { heroByID[id] }

    func hero(byName name: String) async -> Hero? {
        heroByName[name] ?? heroByName[name.lowercased()]
    }

    func heroes(forRole role: HeroRole) async -> [Hero] { heroByRole[role] ?? [] }

    func heroes(forLane lane: HeroLane) async -> [Hero] { heroByLane[lane] ?? [] }

    func searchHeroes(query: String) async -> [Hero] {
        guard !query.isEmpty else { return heroes }
        let lower = query.lowercased()
        return heroes.filter {
            $0.name.lowercased().contains(lower) ||
            $0.primaryRole.rawValue.lowercased().contains(lower) ||
            $0.primaryLane.rawValue.lowercased().contains(lower)
        }
    }

    func allHeroNames() async -> [String] { heroes.map { $0.name } }

    func hero(byNameFuzzy name: String) async -> Hero? {
        if let exact = heroByName[name] { return exact }
        let lower = name.lowercased()
        return heroes.first {
            $0.name.lowercased().contains(lower) || lower.contains($0.name.lowercased())
        }
    }

    // MARK: - Loading

    private func loadFromBundle() async throws -> [Hero] {
        guard let url = Bundle.main.url(forResource: "heroes", withExtension: "json") else {
            throw HeroDatabaseError.bundleFileNotFound
        }
        let data = try Data(contentsOf: url)
        let wrapper = try JSONDecoder().decode(HeroDatabaseWrapper.self, from: data)
        currentPatch = wrapper.patchVersion
        return wrapper.heroes
    }

    func refreshFromRemote(patchVersion: String) async throws {
        let data = try await networkService.fetchHeroDatabase(patchVersion: patchVersion)
        let wrapper = try JSONDecoder().decode(HeroDatabaseWrapper.self, from: data)
        applyHeroes(wrapper.heroes)
        currentPatch = wrapper.patchVersion
    }

    // MARK: - Index Building

    private func applyHeroes(_ newHeroes: [Hero]) {
        heroes = newHeroes
        heroByID = Dictionary(uniqueKeysWithValues: newHeroes.map { ($0.id, $0) })
        heroByName = Dictionary(uniqueKeysWithValues: newHeroes.map { ($0.name, $0) })

        heroByRole = [:]
        heroByLane = [:]
        for hero in newHeroes {
            heroByRole[hero.primaryRole, default: []].append(hero)
            if let sec = hero.secondaryRole { heroByRole[sec, default: []].append(hero) }
            heroByLane[hero.primaryLane, default: []].append(hero)
            if let sec = hero.secondaryLane { heroByLane[sec, default: []].append(hero) }
        }
    }
}

// MARK: - Wrapper
private struct HeroDatabaseWrapper: Codable {
    let patchVersion: String
    let updatedAt: String
    let heroes: [Hero]
}

// MARK: - Errors
enum HeroDatabaseError: Error, LocalizedError {
    case bundleFileNotFound
    case decodingFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .bundleFileNotFound: return "Hero database not found in bundle."
        case .decodingFailed(let msg): return "Failed to decode hero database: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        }
    }
}
