import SwiftUI
import Testing
@testable import BreathRelaxStretch

@MainActor
struct AskButtonTests {
    /// The mic fails closed: any background stops it, and .inactive stops it unless
    /// that inactivity is our own permission alert.
    @Test(arguments: [
        (ScenePhase.active, false, false), (.active, true, false),
        (.inactive, false, true), (.inactive, true, false),
        (.background, false, true), (.background, true, true),
    ])
    func shouldStopListening(_ phase: ScenePhase, _ requestingPermission: Bool, _ expected: Bool) {
        #expect(AskButton.shouldStopListening(phase: phase, requestingPermission: requestingPermission) == expected)
    }
}
