import Foundation
import Combine

// MARK: - Hero Database Service
/// Loads, caches, and keeps the hero database up to date.
///
/// Priority chain on launch:
///   1. Local cache (Documents/heroes_cache.json) — fastest, always up-to-date after first fetch
///   2. Bundle fallback (heroes.json shipped with the IPA)
///   3. Remote fetch from GitHub — runs silently after the local load completes
///
/// The remote check only fires if more than `updateIntervalHours` have elapsed since
/// the last successful remote fetch, or on an explicit `refreshFromRemote()` call.
@MainActor
final class HeroDatabaseService: ObservableObject, HeroDatabaseProtocol {

    // MARK: - Published state

    @Published private(set) var heroes: [Hero] = []
    @Published private(set) var isLoaded: Bool = false
    @Published private(set) var currentPatch: String = "–"
    @Published private(set) var loadError: Error? = nil
    @Published private(set) var isCheckingForUpdates: Bool = false
    @Published private(set) var lastChecked: Date? = nil
    @Published private(set) var updateAvailable: Bool = false

    // MARK: - Configuration

    /// Raw GitHub URL — update this whenever heroes.json moves.
    static let remoteHeroesURL = URL(string:
        "https://raw.githubusercontent.com/auzzy370-wq/mlbb-advisor/main/HayaAI/HayaAI/HeroDatabase/JSON/heroes.json"
    )!

    /// How many hours between automatic background checks.
    static let updateIntervalHours: Double = 6

    // MARK: - Internal

    nonisolated let networkService: NetworkService
    private var heroByID:   [String: Hero] = [:]
    private var heroByName: [String: Hero] = [:]
    private var heroByRole: [HeroRole: [Hero]] = [:]
    private var heroByLane: [HeroLane: [Hero]] = [:]

    private static let cacheFileName = "heroes_cache.json"
    private static let lastCheckedKey = "HeroDB_lastRemoteCheck"

    private static var cacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(cacheFileName)
    }

    // MARK: - Init

    init(networkService: NetworkService = NetworkService()) {
        self.networkService = networkService
        Task {
            try? await loadHeroes()
            await checkForUpdatesIfNeeded()
        }
    }

    // MARK: - HeroDatabaseProtocol

    func loadHeroes() async throws -> [Hero] {
        // 1. Try local cache first (fastest path and stays in sync after updates)
        if let wrapper = loadFromCache() {
            applyHeroes(wrapper.heroes)
            currentPatch = wrapper.patchVersion
            isLoaded = true
            return wrapper.heroes
        }
        // 2. Fallback to bundled JSON
        let loaded = try await loadFromBundle()
        applyHeroes(loaded.heroes)
        currentPatch = loaded.patchVersion
        isLoaded = true
        return loaded.heroes
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

    // MARK: - Auto-update

    /// Checks for a new version in the background if the configured interval has elapsed.
    func checkForUpdatesIfNeeded() async {
        let stored = UserDefaults.standard.object(forKey: Self.lastCheckedKey) as? Date
        let elapsed = stored.map { Date().timeIntervalSince($0) } ?? .greatestFiniteMagnitude
        let intervalSeconds = Self.updateIntervalHours * 3600
        guard elapsed >= intervalSeconds else { return }
        await fetchAndApplyRemoteDatabase()
    }

    /// Forces an immediate fetch regardless of the elapsed-time gate.
    func refreshFromRemote() async {
        await fetchAndApplyRemoteDatabase()
    }

    // MARK: - Private helpers

    private func fetchAndApplyRemoteDatabase() async {
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: Self.remoteHeroesURL)

            // Honour HTTP errors (e.g. 404 if the file is moved)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return
            }

            let wrapper = try JSONDecoder().decode(HeroDatabaseWrapper.self, from: data)

            // Record the check timestamp even if the patch didn't change
            let now = Date()
            UserDefaults.standard.set(now, forKey: Self.lastCheckedKey)
            lastChecked = now

            // Only overwrite local state when the patch is actually different
            guard wrapper.patchVersion != currentPatch else {
                updateAvailable = false
                return
            }

            // Persist to cache and update in-memory state
            saveToCache(data)
            applyHeroes(wrapper.heroes)
            currentPatch = wrapper.patchVersion
            updateAvailable = false

        } catch {
            // Network / decoding failures are non-fatal — keep serving local data
        }
    }

    private func loadFromBundle() async throws -> HeroDatabaseWrapper {
        guard let url = Bundle.main.url(forResource: "heroes", withExtension: "json") else {
            throw HeroDatabaseError.bundleFileNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(HeroDatabaseWrapper.self, from: data)
    }

    private func loadFromCache() -> HeroDatabaseWrapper? {
        let url = Self.cacheURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let wrapper = try? JSONDecoder().decode(HeroDatabaseWrapper.self, from: data)
        else { return nil }
        return wrapper
    }

    private func saveToCache(_ data: Data) {
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    // MARK: - Index building

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

    // Legacy compatibility — kept for callers that pass a patchVersion string
    func refreshFromRemote(patchVersion: String) async throws {
        await fetchAndApplyRemoteDatabase()
    }
}

// MARK: - Wrapper (shared with cache decode)
struct HeroDatabaseWrapper: Codable {
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
        case .bundleFileNotFound:        return "Hero database not found in bundle."
        case .decodingFailed(let msg):   return "Failed to decode hero database: \(msg)"
        case .networkError(let msg):     return "Network error: \(msg)"
        }
    }
}
