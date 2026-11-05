import Testing
import Foundation
@testable import BreathRelaxStretch

struct AskIntentTests {

    @Test func everyRegionIsARealCatalogTag() throws {
        let tags = Set(try SeedDataTests.loadExercises()
            .flatMap { $0["targetBodyParts"] as? [String] ?? [] })
        for area in AskArea.allCases {
            for region in area.regions {
                #expect(tags.contains(region), "\(region) (from \(area.rawValue)) is not a catalog tag")
            }
        }
    }

    @Test func goalRawValuesMatchGoalMeta() {
        #expect(Set(AskGoal.allCases.map(\.rawValue)) == Set(GoalMeta.all.map(\.id)))
    }

    @Test func lowerBackRegions() {
        #expect(AskArea.lowerBack.regions == ["Lower Back", "Spinal Erectors", "Lower Spine"])
    }

    @Test func safetyOrdering() {
        #expect(SafetyLevel.urgent > .concerning && SafetyLevel.concerning > .ok)
    }
}
