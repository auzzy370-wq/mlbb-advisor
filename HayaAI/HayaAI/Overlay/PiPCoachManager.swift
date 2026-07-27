import AVKit
import AVFoundation
import UIKit
import Combine

// MARK: - PiP Display Mode
enum PiPDisplayMode: CaseIterable {
    case coaching       // coaching tips / game state
    case nextBuy        // next item to build this phase
    case counterBuild   // counter item vs enemy comp
}

// MARK: - Build Hint
struct PiPBuildHint {
    let itemName: String
    let reason: String          // e.g. "vs Estes heal"
    let icon: String            // SF symbol
    let isCounter: Bool         // false = core item, true = counter pick
}

// MARK: - PiP Coach Manager
/// Manages the floating Picture-in-Picture coaching window.
///
/// Display priority order (cycles every 8 s):
///   1. Coaching tip  — game state / objective alerts
///   2. Next buy      — next core item for current phase
///   3. Counter build — situational counter item vs enemy picks
@MainActor
final class PiPCoachManager: NSObject, ObservableObject {

    @Published private(set) var isActive: Bool = false
    @Published private(set) var isAvailable: Bool = false

    private var pipController: AVPictureInPictureController?
    private let contentVC = CoachPiPViewController()

    // ── Real OCR data ────────────────────────────────────────────
    private var lastRealDataAt: Date = .distantPast
    private var latestGameTime: String?
    private var latestFriendlyKills: Int?
    private var latestEnemyKills: Int?
    private var latestHero: String?
    private var latestPhase: String = "Waiting"
    private var isCapturing: Bool = false

    // ── Build context (set from draft) ───────────────────────────
    private var playerHeroData: Hero?           // from HeroDatabaseService
    private var enemyHeroes: [Hero] = []        // resolved enemy picks
    private weak var heroDatabase: HeroDatabaseService?

    // ── Mode cycling ─────────────────────────────────────────────
    private var displayModeIndex: Int = 0
    private var modeCycleCounter: Int = 0       // ticks before cycling
    private let ticksPerMode: Int = 8           // ~8 s per mode

    // ── Clock + alerts ───────────────────────────────────────────
    private var clockTask: Task<Void, Never>?
    private var elapsedSeconds: Int = 0
    /// True only while the game is actually live (earlyGame / midGame / lateGame).
    /// The clock does NOT tick during draft, loading, lobby, or idle.
    private var isGameLive: Bool = false
    private var lastSessionPhase: GameSessionPhase = .idle
    private var lastAlertAt: Date = .distantPast
    private var currentAlert: (message: String, icon: String, priority: AlertPriority)?

    override init() {
        super.init()
        isAvailable = AVPictureInPictureController.isPictureInPictureSupported()
    }

    // MARK: - Public API

    func start(from sourceView: UIView) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        guard !isActive else { return }
        activateAudioSession()

        let source = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: sourceView,
            contentViewController: contentVC
        )
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        pipController = pip
        pip.startPictureInPicture()
        startClock()
        push()
    }

    /// Called every time the coaching engine produces a new game state.
    func update(alert: CoachAlert?, gameState: LiveGameState) {
        let incomingPhase = gameState.sessionPhase
        let wasLive = isGameLive
        isGameLive = incomingPhase == .earlyGame || incomingPhase == .midGame || incomingPhase == .lateGame

        // Detect the moment the game goes live — reset clock so it starts at 0:00,
        // not whatever the draft/lobby timer accumulated.
        if isGameLive && !wasLive {
            elapsedSeconds = 0
            latestGameTime = nil         // will be set below if OCR has real data
            latestFriendlyKills = nil
            latestEnemyKills = nil
        }

        // Detect game ending — clear live data so the clock hides again.
        if !isGameLive && wasLive {
            latestGameTime = nil
            latestFriendlyKills = nil
            latestEnemyKills = nil
        }

        // Only trust clock/kill data when the game is actually running.
        if isGameLive {
            if gameState.gameTimeSeconds > 0 {
                let mins = gameState.gameTimeSeconds / 60
                let secs = gameState.gameTimeSeconds % 60
                latestGameTime = String(format: "%d:%02d", mins, secs)
                // Sync internal counter if OCR differs by more than 3 s.
                if abs(gameState.gameTimeSeconds - elapsedSeconds) > 3 {
                    elapsedSeconds = gameState.gameTimeSeconds
                }
                lastRealDataAt = Date()
            }
            if gameState.killScore.friendly > 0 || gameState.killScore.enemy > 0 {
                latestFriendlyKills = gameState.killScore.friendly
                latestEnemyKills = gameState.killScore.enemy
                lastRealDataAt = Date()
            }
        }

        latestPhase = incomingPhase.rawValue
        lastSessionPhase = incomingPhase
        isCapturing = incomingPhase != .idle

        if let alert = alert, alert.priority >= .medium {
            currentAlert = (alert.message, alert.type.icon, alert.priority)
            lastAlertAt = Date()
            push()
        }
    }

    /// Called when the player locks a hero in draft — resolves hero + enemies from database.
    func setDraftContext(heroName: String, enemyHeroNames: [String], database: HeroDatabaseService) {
        heroDatabase = database
        latestHero = heroName

        // Resolve Hero structs (for item lookups)
        Task {
            if !heroName.isEmpty {
                playerHeroData = await database.hero(byNameFuzzy: heroName)
            }
            var resolved: [Hero] = []
            for name in enemyHeroNames where !name.isEmpty {
                if let h = await database.hero(byNameFuzzy: name) { resolved.append(h) }
            }
            enemyHeroes = resolved
            push()
        }
    }

    func setHero(_ heroName: String) {
        latestHero = heroName
        push()
    }

    func stop() {
        clockTask?.cancel()
        clockTask = nil
        pipController?.stopPictureInPicture()
        pipController = nil
        isActive = false
        deactivateAudioSession()
    }

    // MARK: - Clock

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.tick()
            }
        }
    }

    private func tick() {
        // Only advance the game clock while a match is running.
        // During draft, loading, lobby and idle the clock stays hidden (latestGameTime stays nil).
        if isGameLive {
            elapsedSeconds += 1
        }

        // Clear stale alerts after 8 s
        if currentAlert != nil, Date().timeIntervalSince(lastAlertAt) > 8 {
            currentAlert = nil
        }

        // Cycle display mode every ticksPerMode seconds
        modeCycleCounter += 1
        if modeCycleCounter >= ticksPerMode {
            modeCycleCounter = 0
            advanceMode()
        }

        push()
    }

    private func advanceMode() {
        let modes = availableModes()
        guard !modes.isEmpty else { return }
        let currentMode = modes[displayModeIndex % modes.count]
        // Skip nextBuy / counterBuild if no hero data yet
        if currentMode == .nextBuy && playerHeroData == nil { return }
        displayModeIndex = (displayModeIndex + 1) % modes.count
    }

    private func availableModes() -> [PiPDisplayMode] {
        var modes: [PiPDisplayMode] = [.coaching]
        if playerHeroData != nil { modes.append(.nextBuy) }
        if playerHeroData != nil && !enemyHeroes.isEmpty { modes.append(.counterBuild) }
        return modes
    }

    // MARK: - Display

    private func push() {
        guard isActive else { return }

        let hasRealData = Date().timeIntervalSince(lastRealDataAt) < 10
        let modes = availableModes()
        let mode = modes.isEmpty ? .coaching : modes[displayModeIndex % modes.count]

        // High-priority coaching alert always overrides mode cycling
        let effectiveMode: PiPDisplayMode = (currentAlert != nil) ? .coaching : mode

        let buildHint: PiPBuildHint? = {
            switch effectiveMode {
            case .nextBuy:      return nextBuyHint()
            case .counterBuild: return counterBuildHint()
            case .coaching:     return nil
            }
        }()

        let (message, icon, priority) = resolveMessage(hasRealData: hasRealData)

        // Only show a clock when the match is actually running.
        // During draft/loading/lobby the clock stays nil → renders as "--:--".
        let displayTime: String? = isGameLive
            ? (latestGameTime ?? (elapsedSeconds > 0 ? formattedElapsed() : nil))
            : nil

        let state = PiPDisplayState(
            gameTime: displayTime,
            friendlyKills: isGameLive ? latestFriendlyKills : nil,
            enemyKills: isGameLive ? latestEnemyKills : nil,
            heroName: latestHero,
            phase: latestPhase,
            isLiveData: hasRealData && isGameLive,
            message: message,
            icon: icon,
            priority: priority,
            isCapturing: isCapturing,
            buildHint: buildHint,
            displayMode: effectiveMode
        )
        contentVC.update(state: state)
    }

    // MARK: - Build Logic

    /// Next core item for the player's hero based on the current game phase.
    private func nextBuyHint() -> PiPBuildHint? {
        guard let hero = playerHeroData else { return nil }
        let items = hero.preferredItems
        guard !items.isEmpty else { return nil }

        // Slot index based on phase / elapsed time
        let slotIndex: Int
        switch elapsedSeconds {
        case 0..<240:   slotIndex = 0          // <4 min  → boots
        case 240..<480: slotIndex = 1          // 4-8 min → 1st core
        case 480..<720: slotIndex = 2          // 8-12 min
        case 720..<960: slotIndex = 3          // 12-16 min
        default:        slotIndex = min(items.count - 1, 4)   // 16+ min
        }

        let item = items[min(slotIndex, items.count - 1)]
        return PiPBuildHint(
            itemName: item.name,
            reason: "Slot \(slotIndex + 1) — \(hero.name) core",
            icon: "cart.fill",
            isCounter: false
        )
    }

    /// Best counter item for the current enemy composition.
    private func counterBuildHint() -> PiPBuildHint? {
        guard let hero = playerHeroData else { return nil }

        // Check for high-priority situational needs
        let enemyRoles = Set(enemyHeroes.flatMap { $0.roles })
        let enemyNames = Set(enemyHeroes.map { $0.name })

        // Anti-heal: any healer in enemy team
        let healers: Set<String> = ["Estes", "Rafaela", "Floryn", "Angela", "Uranus", "Ruby",
                                    "Carmilla", "Alice", "Esmeralda", "Kalea", "Minotaur"]
        if !healers.isDisjoint(with: enemyNames) {
            let antiHealItem = hero.primaryRole == .mage || hero.secondaryRole == .mage
                ? "Necklace of Durance"
                : "Sea Halberd"
            return PiPBuildHint(
                itemName: antiHealItem,
                reason: "Anti-heal vs \(enemyHeroes.filter { healers.contains($0.name) }.map { $0.name }.first ?? "healer")",
                icon: "cross.circle.fill",
                isCounter: true
            )
        }

        // Magic pen: mostly mages or magic damage enemies
        let magicEnemyCount = enemyHeroes.filter { $0.damageType == .magic }.count
        if magicEnemyCount >= 2 {
            let magicDefItem: String
            switch hero.primaryRole {
            case .tank, .fighter:   magicDefItem = "Athena's Shield"
            case .marksman:         magicDefItem = "Athena's Shield"
            default:                magicDefItem = "Athena's Shield"
            }
            return PiPBuildHint(
                itemName: magicDefItem,
                reason: "vs \(magicEnemyCount) magic heroes",
                icon: "shield.fill",
                isCounter: true
            )
        }

        // Armor pen: enemy has multiple tanks/fighters
        let tankCount = enemyHeroes.filter { $0.primaryRole == .tank || $0.primaryRole == .fighter }.count
        if tankCount >= 2 && (hero.damageType == .physical) {
            return PiPBuildHint(
                itemName: "Malefic Roar",
                reason: "vs \(tankCount) tanky enemies",
                icon: "bolt.fill",
                isCounter: true
            )
        }

        // Fallback to hero's own counter item list
        if let counterItem = hero.counterItems.first {
            return PiPBuildHint(
                itemName: counterItem.name,
                reason: "Situational pick",
                icon: "arrow.uturn.backward.circle.fill",
                isCounter: true
            )
        }

        // Show situational item from hero's list
        if let situational = hero.situationalItems.first {
            return PiPBuildHint(
                itemName: situational.name,
                reason: "vs current comp",
                icon: "wrench.fill",
                isCounter: false
            )
        }

        return nil
    }

    // MARK: - Message resolution

    private func resolveMessage(hasRealData: Bool) -> (String, String, AlertPriority) {
        if let alert = currentAlert { return (alert.message, alert.icon, alert.priority) }

        // In lobby / draft / loading, show a status message — never objective timers.
        if !isGameLive { return preGameMessage() }

        if hasRealData { return realDataTip() }
        return timedFallbackTip()
    }

    /// Status messages shown before the match starts.
    private func preGameMessage() -> (String, String, AlertPriority) {
        switch lastSessionPhase {
        case .idle:
            return ("Start a broadcast to begin coaching", "dot.radiowaves.left.and.right", .low)
        case .draft:
            return ("Draft phase — tap slots in Haya AI to add picks", "person.3.fill", .low)
        case .loading:
            return ("Loading into game...", "hourglass", .low)
        default:
            return ("Waiting for game to start", "clock", .low)
        }
    }

    private func realDataTip() -> (String, String, AlertPriority) {
        let t = elapsedSeconds
        let f = latestFriendlyKills ?? 0
        let e = latestEnemyKills ?? 0

        if e - f >= 5 { return ("Big deficit — group up, avoid solo fights", "exclamationmark.triangle.fill", .high) }
        if f - e >= 3 { return ("You're ahead — push towers and take objectives", "bolt.fill", .medium) }
        if e - f >= 3 { return ("You're behind — play safe and farm to scale", "shield.fill", .medium) }

        switch t {
        case 210..<250: return ("Turtle spawning soon — push and rotate", "tortoise.fill", .high)
        case 250..<300: return ("Turtle is UP — contest it now!", "exclamationmark.triangle.fill", .critical)
        case 390..<430: return ("Lord spawns at 8:00 — set up vision", "crown.fill", .high)
        case 430..<500: return ("Lord is active — win teamfight to secure!", "crown.fill", .critical)
        case 600..<660: return ("Group mid — rotate for objectives", "person.3.fill", .medium)
        default:
            switch latestPhase {
            case "Early Game": return ("Track minimap — monitor enemy jungler", "map.fill", .low)
            case "Mid Game":   return ("Group for objectives — don't split", "figure.walk", .low)
            case "Late Game":  return ("One teamfight can end the game — stay together", "flag.checkered", .medium)
            default:           return ("Watching your game...", "eye.fill", .low)
            }
        }
    }

    /// Fallback tips shown when the game IS live but no OCR data has arrived yet.
    private func timedFallbackTip() -> (String, String, AlertPriority) {
        // First few seconds — just say we're reading.
        if elapsedSeconds < 10 {
            return ("Haya AI is reading your screen...", "viewfinder", .low)
        }

        let tips: [(String, String)] = [
            ("Check minimap every few seconds", "map.fill"),
            ("Ward jungle entrances to avoid ganks", "eye.fill"),
            ("Farm between fights for gold advantage", "dollarsign.circle.fill"),
            ("Focus objectives over kills", "star.fill"),
            ("Stay behind your tank in teamfights", "shield.fill"),
            ("Use pings to communicate with team", "bubble.left.fill"),
        ]
        let idx = (elapsedSeconds / 20) % tips.count
        return (tips[idx].0, tips[idx].1, .low)
    }

    private func formattedElapsed() -> String {
        String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    // MARK: - Audio Session

    private func activateAudioSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? s.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - AVPictureInPictureControllerDelegate
extension PiPCoachManager: AVPictureInPictureControllerDelegate {

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ c: AVPictureInPictureController
    ) { Task { @MainActor in self.isActive = true; self.push() } }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ c: AVPictureInPictureController
    ) { Task { @MainActor in self.isActive = false } }

    nonisolated func pictureInPictureController(
        _ c: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) { Task { @MainActor in
        self.isActive = false
        print("[PiP] Failed: \(error.localizedDescription)")
    } }
}
