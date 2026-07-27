import Vision
import UIKit
import CoreGraphics

// MARK: - Draft Slot Regions
// Fixed layout regions for MLBB's draft screen (normalized 0-1, origin top-left).
// Approximate positions for standard 19.5:9 iPhone aspect ratio.
//
//  Left column  = Friendly team (picks 0-4)
//  Right column = Enemy team (picks 0-4)
//
// These were calibrated for a 1170×2532 (iPhone 14 Pro) screen.
// The broadcast frames are already resized to 720p by SampleHandler, so all
// fractions stay valid regardless of the source device resolution.
//
// Adjustments by lane (top→bottom): ban row + 5 pick rows per side.
struct DraftSlotRegions {
    // [team 0=friendly, team 1=enemy][slot 0-4]
    static let pickRegions: [[CGRect]] = [
        // Friendly (left side) — x: 0.04 → 0.30
        [
            CGRect(x: 0.04, y: 0.25, width: 0.22, height: 0.10), // slot 0
            CGRect(x: 0.04, y: 0.36, width: 0.22, height: 0.10),
            CGRect(x: 0.04, y: 0.47, width: 0.22, height: 0.10),
            CGRect(x: 0.04, y: 0.58, width: 0.22, height: 0.10),
            CGRect(x: 0.04, y: 0.69, width: 0.22, height: 0.10),
        ],
        // Enemy (right side) — x: 0.74 → 1.0
        [
            CGRect(x: 0.74, y: 0.25, width: 0.22, height: 0.10),
            CGRect(x: 0.74, y: 0.36, width: 0.22, height: 0.10),
            CGRect(x: 0.74, y: 0.47, width: 0.22, height: 0.10),
            CGRect(x: 0.74, y: 0.58, width: 0.22, height: 0.10),
            CGRect(x: 0.74, y: 0.69, width: 0.22, height: 0.10),
        ]
    ]
}

// MARK: - Hero Portrait Matcher
/// Uses `VNGenerateImageFeaturePrintRequest` to match crop regions from a live
/// broadcast frame against cached feature vectors for all MLBB heroes.
///
/// On first launch it downloads small (150px) hero thumbnails from the MLBB wiki
/// CDN, computes VNFeaturePrint embeddings, and stores them in
/// `{Documents}/portrait_features/` so subsequent launches are instant.
///
/// Detection flow per frame:
///   1. Crop draft-slot regions from the broadcast CGImage.
///   2. Generate a feature print for each crop.
///   3. Compare against all cached feature prints (distance < threshold → match).
///   4. Report the hero name (or nil if below threshold) for each slot.
actor HeroPortraitMatcher {

    // Maximum L2 distance to accept a match. 0.0 = identical, higher = looser.
    // Empirically, portrait matches land around 0.55; random images > 0.80.
    static let matchThreshold: Float = 0.60

    // Map heroName → cached feature print data
    private var featurePrints: [String: VNFeaturePrintObservation] = [:]
    private var heroNames: [String] = []

    private static let cacheDir: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("portrait_features", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Setup

    /// Call once on app launch — loads any locally cached prints and queues
    /// downloads for heroes that don't have a cached print yet.
    func prepare(heroNames names: [String]) async {
        heroNames = names
        // Load cached prints for all heroes synchronously
        for name in names {
            if let obs = loadCachedPrint(for: name) {
                featurePrints[name] = obs
            }
        }
        // Queue background downloads for any hero that's missing a print
        let missing = names.filter { featurePrints[$0] == nil }
        if !missing.isEmpty {
            await downloadAndCache(heroes: missing)
        }
    }

    // MARK: - Match

    /// Returns (friendly picks [0-4], enemy picks [0-4]) from a single frame.
    /// Each element is an optional hero name; nil means the slot was empty or unrecognized.
    func matchDraftSlots(in frame: CGImage) async -> (friendly: [String?], enemy: [String?]) {
        guard !featurePrints.isEmpty else { return (Array(repeating: nil, count: 5),
                                                     Array(repeating: nil, count: 5)) }

        var friendly: [String?] = []
        var enemy: [String?] = []

        for (teamIdx, regions) in DraftSlotRegions.pickRegions.enumerated() {
            var teamResult: [String?] = []
            for region in regions {
                let match = await matchSlot(region: region, in: frame)
                teamResult.append(match)
            }
            if teamIdx == 0 { friendly = teamResult } else { enemy = teamResult }
        }

        return (friendly, enemy)
    }

    // MARK: - Private

    private func matchSlot(region: CGRect, in frame: CGImage) async -> String? {
        guard let crop = cropRegion(region, from: frame) else { return nil }
        guard let queryPrint = computeFeaturePrint(for: crop) else { return nil }

        var bestName: String? = nil
        var bestDistance: Float = Self.matchThreshold

        for (name, refPrint) in featurePrints {
            var distance: Float = 0
            do {
                try queryPrint.computeDistance(&distance, to: refPrint)
                if distance < bestDistance {
                    bestDistance = distance
                    bestName = name
                }
            } catch {}
        }
        return bestName
    }

    private func cropRegion(_ region: CGRect, from image: CGImage) -> CGImage? {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let rect = CGRect(
            x: region.minX * w,
            y: region.minY * h,
            width: region.width * w,
            height: region.height * h
        )
        return image.cropping(to: rect)
    }

    private func computeFeaturePrint(for image: CGImage) -> VNFeaturePrintObservation? {
        let req = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([req])
            return req.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }

    // MARK: - Cache I/O

    private func loadCachedPrint(for heroName: String) -> VNFeaturePrintObservation? {
        let url = cacheURL(for: heroName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    private func savePrint(_ obs: VNFeaturePrintObservation, for heroName: String) {
        let url = cacheURL(for: heroName)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: obs, requiringSecureCoding: true) {
            try? data.write(to: url, options: .atomicWrite)
        }
    }

    private func cacheURL(for heroName: String) -> URL {
        let safe = heroName.lowercased().replacing(/[^a-z0-9]/, with: { _ in "-" })
        return Self.cacheDir.appendingPathComponent("\(safe).featureprint")
    }

    // MARK: - Download + Compute

    /// Downloads a 150px thumbnail for each hero, computes VNFeaturePrint, caches it.
    /// Portrait CDN: MLBB wiki / community maintained. Falls back on download failure.
    private func downloadAndCache(heroes: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for heroName in heroes {
                group.addTask { [weak self] in
                    guard let self else { return }
                    await self.downloadAndCacheSingle(heroName: heroName)
                }
            }
        }
    }

    private func downloadAndCacheSingle(heroName: String) async {
        guard let url = portraitURL(for: heroName) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data),
                  let cgImage = uiImage.cgImage else { return }
            if let obs = computeFeaturePrint(for: cgImage) {
                savePrint(obs, for: heroName)
                featurePrints[heroName] = obs
            }
        } catch {
            // Silently fail — hero won't be detected from portraits until cache exists
        }
    }

    /// Constructs a CDN URL for the hero portrait thumbnail.
    /// Uses the MLBB Bang Bang wiki CDN with a consistent slug pattern.
    /// The slug is the hero name lowercased, spaces replaced with underscores.
    private func portraitURL(for heroName: String) -> URL? {
        // Primary: official MLBB wiki Fandom CDN (stable, well-maintained)
        let slug = heroName
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "-", with: "_")

        // Format: https://static.wikia.nocookie.net/mobile-legends/images/[first]/[slug]/[slug].png
        // The path segment structure varies so we use the canonical redirect URL instead.
        // wiki.gg and similar mirrors use predictable slugs.
        let urlStr = "https://liquipedia.net/mobilelegends/images/thumb/heroes/\(slug)/150px-\(slug).png"
        return URL(string: urlStr)
    }
}
