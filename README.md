# Haya AI – Mobile Legends Draft Assistant

**Haya AI** is a production-quality iOS application that analyzes the Mobile Legends: Bang Bang draft screen in real time and recommends hero picks, bans, builds, emblems, battle spells, and strategic guidance.

---

## Architecture Overview

```
HayaAI/
├── App/                        # Entry point, AppDelegate, AppRouter, RootView
├── Models/                     # Core data structures (Hero, DraftState, Recommendation, etc.)
├── Protocols/                  # Dependency-injection interfaces for every engine
├── ReplayKit/                  # ReplayKitManager – screen capture at target FPS
├── OCREngine/                  # Vision Framework OCR, text classification, hero name matching
├── VisionEngine/
│   ├── Core/                   # VisionEngine – orchestrates all detectors concurrently
│   ├── Detectors/              # HeroPortraitDetector (ML + OCR fallback), PhaseDetector, TimerDetector
│   └── Processors/             # FrameProcessor (pre-processing), StateChangeDetector (dedup)
├── DraftEngine/                # DraftStateManager + DraftStateReconciler
├── HeroDatabase/
│   ├── JSON/heroes.json        # Versioned hero database (10 heroes in MVP, expandable)
│   └── Services/               # HeroDatabaseService – loading, caching, querying
├── RecommendationEngine/       # 8-dimension hero scoring, top-5 recommendations
├── ItemEngine/                 # Build recommendation (core/situational/counter/anti-heal)
├── StrategyEngine/             # Game plan, target priority, objective timing
├── MetaEngine/                 # Patch-aware meta scoring, top meta heroes
├── Authentication/             # Firebase Auth (email/password, Apple Sign In stub)
├── Dashboard/                  # Home screen with meta heroes and quick actions
├── DraftAssistant/             # Live draft UI – board, recommendations, team analysis, strategy
├── Analytics/                  # Win rates, charts, match history
├── Settings/                   # User preferences
├── Networking/                 # URLSession wrapper, OpenAI integration
├── SharedComponents/           # GlassCard, HayaButton, ConfidenceBar, design tokens
└── Resources/                  # Info.plist, asset catalog
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 6 |
| UI | SwiftUI |
| Architecture | MVVM + Actor concurrency |
| Screen Capture | ReplayKit |
| OCR / Vision | Vision Framework, VNRecognizeTextRequest |
| Hero Detection | CoreML + VNCoreMLRequest (OCR fallback in MVP) |
| Database | JSON bundle (SQLite/Realm migration path) |
| Authentication | Firebase Auth |
| Networking | URLSession + async/await |
| AI Explanations | OpenAI GPT-4o-mini (optional) |
| Concurrency | Swift actors, structured concurrency, Combine |

---

## Key Features

### Vision Engine Pipeline
```
ReplayKit Frame → FrameProcessor → VisionEngine ──┬── OCREngine (text, timer, phase)
                                                   ├── HeroPortraitDetector (ML / OCR)
                                                   ├── PhaseDetector
                                                   └── TimerDetector
                                                         ↓
                                               FrameAnalysisResult
                                                         ↓
                                               DraftStateManager (reconciles + deduplicates)
                                                         ↓
                                               DraftState (published to UI)
                                                         ↓
                                               RecommendationEngine (5 async score dimensions)
                                                         ↓
                                               Top 5 HeroRecommendations + Strategy
```

### Recommendation Scoring (8 dimensions, weighted)
| Dimension | Weight | Description |
|---|---|---|
| Counter Score | 20% | How well hero counters enemy picks |
| Synergy Score | 20% | How well hero fits with allies |
| Lane Score | 15% | Fills team's lane/role gaps |
| Meta Score | 15% | Current patch tier strength |
| Scaling Score | 10% | Late-game power |
| Comfort Score | 10% | Player familiarity / win rate |
| Difficulty Score | 5% | Hero execution complexity |
| Execution Score | 5% | Combo reliability in this comp |

### Hero Database
10 heroes in the MVP JSON database. Each entry includes:
- Full stats (mobility, CC, burst, sustain, scaling, etc.)
- Core and situational builds
- Best spell and emblem
- Combo steps and power spikes
- Rotation guide
- Professional and rank win/pick rates
- Counter and counter-by lists

Database is versioned and supports OTA patch updates without app rebuild.

---

## Setup Instructions

### Prerequisites
- Xcode 15+
- iOS 17+ device or simulator
- CocoaPods / SPM (Firebase, Supabase, SQLite.swift)

### Steps
1. Clone the repository
2. Open `HayaAI/HayaAI.xcodeproj` in Xcode
3. Add `GoogleService-Info.plist` to the `HayaAI/Resources/` folder (obtain from Firebase Console)
4. Resolve Swift Package dependencies (File → Packages → Resolve)
5. Set your development team in Signing & Capabilities
6. Build and run on a real device for screen capture (ReplayKit requires physical device)

### Environment Variables / Secrets
| Key | Description |
|---|---|
| `OPENAI_API_KEY` | Optional – enables AI-powered pick explanations |
| `SUPABASE_URL` | Optional – cloud sync and leaderboards |
| `SUPABASE_ANON_KEY` | Optional – Supabase anonymous key |

---

## Performance Targets

| Metric | Target |
|---|---|
| Frame capture rate | 15 fps (configurable) |
| Detection latency | < 250ms per frame |
| Recommendation latency | < 500ms |
| UI frame rate | 60 fps |
| Draft state dedup window | 500ms |

---

## Future Roadmap

- [ ] Voice assistant integration (AVSpeechSynthesizer)
- [ ] Live in-match recommendations (cooldown tracking)
- [ ] CoreML hero portrait classifier (replace OCR fallback)
- [ ] Objective tracking overlay
- [ ] Cloud sync via Supabase
- [ ] ML-powered recommendation refinement (on-device model fine-tuning)
- [ ] Enemy cooldown tracking
- [ ] Full analytics dashboard with charts

---

## Project Status

MVP – All core modules implemented and wired together:
- ✅ ReplayKit screen capture (15fps, throttled)
- ✅ Vision Engine with OCR (text, timer, phase, hero name)
- ✅ Draft State Manager with majority-vote smoothing
- ✅ Hero database (10 heroes, JSON, patch-versioned)
- ✅ 8-dimension recommendation engine
- ✅ Item recommendation engine
- ✅ Strategy engine
- ✅ Firebase authentication
- ✅ Modern glassmorphism UI
- ✅ Unit tests (recommendation, draft state, OCR, hero database)
