import Testing
@testable import BreathRelaxStretch

struct KeywordIntentExtractorTests {
    private let extractor = KeywordIntentExtractor()

    @Test func englishLowerBackPain() {
        let i = extractor.intent(for: "give me exercises that can ease my lower back pain")
        #expect(i.areas == [.lowerBack])
        #expect(i.goal == .pain_relief)
        #expect(i.minutes == nil)
        #expect(i.seriousness == .ok)
        #expect(i.isOffTopic == false)
    }

    @Test func sidesAreIgnored() {
        let i = extractor.intent(for: "my left hip is tight")
        #expect(i.areas == [.hips])
        #expect(i.goal == .flexibility)
    }

    @Test func minutesAreParsed() {
        let i = extractor.intent(for: "5 minute neck stretch")
        #expect(i.areas == [.neck])
        #expect(i.minutes == 5)
    }

    @Test(arguments: [
        ("dolor de espalda baja", AskArea.lowerBack),
        ("j'ai mal au bas du dos", .lowerBack),
        ("腰疼", .lowerBack),
        ("me duele la zona lumbar", .lowerBack),
        ("douleur aux lombaires", .lowerBack),
        ("my back hurts", .lowerBack),
        ("tension en el cuello", .neck),
        ("les épaules tendues", .shoulders),
        ("肩膀酸", .shoulders),
    ])
    func otherLanguagesAndSynonyms(_ text: String, _ area: AskArea) {
        #expect(extractor.intent(for: text).areas == [area])
    }

    @Test(arguments: [
        ("dolor de espalda baja", AskGoal.pain_relief),
        ("j'ai mal au bas du dos", .pain_relief),
        ("腰疼", .pain_relief),
        ("estoy estresado", .stress_relief),
        ("je suis anxieux", .stress_relief),
        ("我很焦虑", .stress_relief),
        ("necesito dormir", .unwind),
        ("pour mieux dormir", .unwind),
        ("睡前放松", .unwind),
        ("good morning stretch", .wake_up),
        ("quiero respirar mejor", .better_breathing),
        ("estoy rígido", .flexibility),
    ])
    func goals(_ text: String, _ goal: AskGoal) {
        #expect(extractor.intent(for: text).goal == goal)
    }

    @Test func goalOnly() {
        let i = extractor.intent(for: "help me sleep")
        #expect(i.areas.isEmpty)
        #expect(i.goal == .unwind)
    }

    @Test func multipleAreas() {
        #expect(Set(extractor.intent(for: "tight hamstrings and calves").areas) == [.hamstrings, .calves])
    }

    @Test func longestPhraseWins() {
        #expect(extractor.intent(for: "upper back and lower back").areas.count == 2)
        #expect(extractor.intent(for: "tight hip flexors").areas == [.hipFlexors])
        #expect(extractor.intent(for: "stiff upper back").areas == [.upperBack])
    }

    @Test func painBeatsTight() {
        #expect(extractor.intent(for: "my tight neck hurts").goal == .pain_relief)
    }

    @Test func wordBoundaries() {
        #expect(extractor.intent(for: "I lost my backpack").isEmpty)
        #expect(extractor.intent(for: "nice necklace").isEmpty)
    }

    @Test(arguments: [
        ("10 minutos de cuello", 10), ("7 minutes pour le cou", 7), ("5分钟颈部", 5),
        ("quick neck stretch", 3), ("algo rápido para el cuello", 3), ("快速放松脖子", 3),
        ("2 min neck", 2),
    ])
    func minutes(_ text: String, _ expected: Int) {
        #expect(extractor.intent(for: text).minutes == expected)
    }

    @Test func explicitMinutesBeatQuick() {
        #expect(extractor.intent(for: "quick 8 minute neck").minutes == 8)
    }

    @Test func offTopicIsEmpty() {
        let i = extractor.intent(for: "what's the weather")
        #expect(i.isEmpty)
        #expect(i.isOffTopic == false)
    }

    @Test func asyncExtractMatchesSync() async throws {
        let text = "5 minute neck stretch"
        #expect(try await extractor.extract(text) == extractor.intent(for: text))
    }
}
