import Testing
@testable import BreathRelaxStretch

@MainActor
struct SafetyScreenerTests {
    @Test(arguments: [
        "I have chest pain", "DOLOR EN EL PECHO", "douleur thoracique",
        "j'ai une douleur à la poitrine", "j’ai une douleur a la poitrine", "胸口疼",
        "I can’t breathe", "shortness of breath", "I think I'm having a heart attack",
        "dolor de pecho", "呼吸困难",
    ])
    func urgent(_ text: String) {
        #expect(SafetyScreener.screen(text) == .urgent)
    }

    @Test(arguments: [
        "sharp pain shooting down my leg", "my foot feels numb", "hormigueo en la pierna",
        "engourdi", "腿发麻", "my back hurts after a fall",
    ])
    func concerning(_ text: String) {
        #expect(SafetyScreener.screen(text) == .concerning)
    }

    @Test(arguments: [
        "give me exercises that can ease my lower back pain", "tight hamstrings",
        "dolor de espalda baja", "", "🙂", "give me a number of hip stretches",
        "my fellow runner said try this", "sharpen my focus with breathing",
        "breaststroke drills", "quiero un empire state tour",
    ])
    func ok(_ text: String) {
        #expect(SafetyScreener.screen(text) == .ok)
    }

    @Test func crossLanguage() {
        #expect(SafetyScreener.screen("please help me, no puedo respirar right now") == .urgent)
    }

    @Test func urgentBeatsConcerning() {
        #expect(SafetyScreener.screen("sharp chest pain") == .urgent)
    }

    @Test func normalizeEquivalences() {
        #expect(SafetyScreener.normalize("douleur à la poitrine") == SafetyScreener.normalize("douleur a la poitrine"))
        #expect(SafetyScreener.normalize("can’t") == "can't")
        #expect(SafetyScreener.normalize("  A   B\n") == "a b")
    }
}
