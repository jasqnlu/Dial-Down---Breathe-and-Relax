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

    @Test func conversionCarriesCountAndNewRoutine() {
        let generated = GeneratedIntent(areas: [.neck], goal: nil, minutes: nil, count: 3,
                                        wantsNewRoutine: true, seriousness: .ok, isOffTopic: false)
        let i = generated.toIntent()
        #expect(i.count == 3)
        #expect(i.wantsNewRoutine)
    }

    @Test(arguments: [(0, nil), (-2, nil), (1, 1), (10, 10), (40, 10)] as [(Int, Int?)])
    func conversionClampsCount(_ raw: Int, _ expected: Int?) {
        let i = GeneratedIntent(areas: [], goal: nil, minutes: nil, count: raw,
                                wantsNewRoutine: false, seriousness: .ok, isOffTopic: false).toIntent()
        #expect(i.count == expected)
    }
}
