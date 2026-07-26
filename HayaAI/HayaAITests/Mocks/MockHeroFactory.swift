import Foundation
@testable import HayaAI

enum MockHeroFactory {
    static func makeTank(id: String = "test_tank", name: String = "TestTank") -> Hero {
        Hero(
            id: id, name: name, title: nil, imageURL: nil,
            primaryRole: .tank, secondaryRole: nil,
            primaryLane: .roam, secondaryLane: nil,
            damageType: .physical, difficulty: .easy,
            earlyStrength: 8, midStrength: 7, lateStrength: 6,
            mobility: 7, crowdControl: 9, burst: 4, sustain: 7,
            objectiveControl: 5, waveClear: 3, scaling: 5,
            strongAgainst: ["Assassin"], weakAgainst: ["Mage"],
            counterHeroes: [], counteredBy: [],
            preferredItems: [], situationalItems: [], counterItems: [],
            bestSpell: .flicker, bestEmblem: .tank,
            talents: [], combos: [], rotationGuide: "Roam and CC",
            powerSpikes: [],
            draftPriority: 8, banPriority: 7, metaScore: 7.5,
            professionalPickRate: 0.4, professionalWinRate: 0.52, rankWinRate: 0.50
        )
    }

    static func makeMarksman(id: String = "test_mm", name: String = "TestMM") -> Hero {
        Hero(
            id: id, name: name, title: nil, imageURL: nil,
            primaryRole: .marksman, secondaryRole: nil,
            primaryLane: .gold, secondaryLane: nil,
            damageType: .physical, difficulty: .moderate,
            earlyStrength: 6, midStrength: 8, lateStrength: 10,
            mobility: 5, crowdControl: 2, burst: 8, sustain: 3,
            objectiveControl: 7, waveClear: 7, scaling: 10,
            strongAgainst: ["Tank"], weakAgainst: ["Assassin"],
            counterHeroes: [], counteredBy: ["Lancelot"],
            preferredItems: [], situationalItems: [], counterItems: [],
            bestSpell: .inspire, bestEmblem: .marksman,
            talents: [], combos: [], rotationGuide: "Scale and poke",
            powerSpikes: [],
            draftPriority: 8.5, banPriority: 7, metaScore: 8.5,
            professionalPickRate: 0.5, professionalWinRate: 0.53, rankWinRate: 0.51
        )
    }

    static func makeAssassin(id: String = "test_sin", name: String = "TestSin") -> Hero {
        Hero(
            id: id, name: name, title: nil, imageURL: nil,
            primaryRole: .assassin, secondaryRole: nil,
            primaryLane: .jungle, secondaryLane: nil,
            damageType: .physical, difficulty: .hard,
            earlyStrength: 7, midStrength: 9, lateStrength: 7,
            mobility: 10, crowdControl: 3, burst: 10, sustain: 3,
            objectiveControl: 6, waveClear: 5, scaling: 7,
            strongAgainst: ["Marksman", "Mage"], weakAgainst: ["Tank"],
            counterHeroes: ["TestMM"], counteredBy: ["TestTank"],
            preferredItems: [], situationalItems: [], counterItems: [],
            bestSpell: .retribution, bestEmblem: .assassin,
            talents: [], combos: [], rotationGuide: "Gank and snowball",
            powerSpikes: [],
            draftPriority: 9, banPriority: 8.5, metaScore: 9,
            professionalPickRate: 0.7, professionalWinRate: 0.55, rankWinRate: 0.50
        )
    }

    static func sampleHeroes() -> [Hero] {
        [makeTank(), makeMarksman(), makeAssassin()]
    }
}
