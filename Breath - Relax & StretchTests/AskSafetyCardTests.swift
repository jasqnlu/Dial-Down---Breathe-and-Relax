import Foundation
import Testing
@testable import BreathRelaxStretch

@MainActor
struct AskSafetyCardTests {
    @Test(arguments: [
        ("CN", "120"), ("JP", "119"), ("KR", "119"), ("TW", "119"),
        ("US", "911"), ("CA", "911"), ("MX", "911"), ("AR", "911"),
        ("BR", "192"), ("CL", "131"),
        ("GB", "999"), ("AU", "000"), ("NZ", "111"), ("IN", "112"),
        ("FR", "112"), ("DE", "112"), ("ES", "112"),
    ])
    func emergencyNumberByRegion(_ region: String, _ number: String) {
        #expect(AskSafetyCard.emergencyNumber(for: Locale.Region(region)) == number)
    }

    @Test func unknownRegionUses112() {
        #expect(AskSafetyCard.emergencyNumber(for: nil) == "112")
    }
}
