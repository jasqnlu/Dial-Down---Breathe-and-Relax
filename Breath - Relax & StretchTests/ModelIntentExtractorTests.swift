import Testing
@testable import BreathRelaxStretch

@MainActor
struct ModelIntentExtractorTests {
    @Test func conversionPreservesFields() {
        let generated = GeneratedIntent(areas: [.lowerBack], goal: .pain_relief, minutes: 7,
                                        seriousness: .concerning, isOffTopic: false)
        #expect(generated.toIntent() == AskIntent(areas: [.lowerBack], goal: .pain_relief, minutes: 7,
                                                  seriousness: .concerning, isOffTopic: false))
    }

    @Test func conversionClampsAndDedupes() {
        let deduped = GeneratedIntent(areas: [.neck, .shoulders, .neck, .shoulders, .hips],
                                      goal: nil, minutes: 500, seriousness: .ok, isOffTopic: false).toIntent()
        #expect(deduped.areas == [.neck, .shoulders, .hips])
        #expect(deduped.minutes == 20)

        let zero = GeneratedIntent(areas: [], goal: nil, minutes: 0, seriousness: .ok, isOffTopic: false).toIntent()
        #expect(zero.minutes == nil)
    }
}
