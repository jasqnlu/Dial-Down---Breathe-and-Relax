import Testing
@testable import BreathRelaxStretch

@MainActor
struct SafetyScreenerTests {
    @Test(arguments: [
        "I have chest pain", "DOLOR EN EL PECHO", "douleur thoracique",
        "j'ai une douleur à la poitrine", "j’ai une douleur a la poitrine", "胸口疼",
        "I can’t breathe", "shortness of breath", "I think I'm having a heart attack",
        "dolor de pecho", "呼吸困难",
        "I lost bladder control", "no bowel control since this morning", "I lost control of my bowels",
        "some incontinence today", "I can't move my leg", "I cannot move my legs",
        "I keep passing out", "I blacked out", "no puedo mover las piernas",
        "perdí el control de esfínteres", "je n'ai plus le contrôle de la vessie",
        "大小便失禁", "有点失禁", "腿动不了",
    ])
    func urgent(_ text: String) {
        #expect(SafetyScreener.screen(text) == .urgent)
    }

    @Test(arguments: [
        "sharp pain shooting down my leg", "my foot feels numb", "hormigueo en la pierna",
        "engourdi", "腿发麻", "my back hurts after a fall",
        // inflections and spec red flags
        "my ankle is swelling", "my fingers are tingly", "numbing pain", "my hand numbed up",
        "I accidentally twisted it", "pain shoots down my arm", "a stabbing pain in my hip",
        "my neck is worsening", "it gets worse at night", "it won't go away", "it wont go away",
        "it doesn't go away", "the pain is not going away", "my hip has hurt for months",
        "I had a fall yesterday", "bad fall on the ice",
        "dolor agudo en la rodilla", "dolores punzantes en el brazo", "hormigueos en la mano", "empeoró ayer",
        "hinchazón en el tobillo", "tengo la pierna adormecida", "tuve un accidente de coche",
        "me caí ayer", "me duele desde hace semanas",
        "une douleur lancinante", "des fourmillements dans la main", "j'ai le genou gonflé",
        "ça picote", "je suis tombée hier", "mal au dos depuis des semaines",
        "车祸后脖子疼", "我跌倒了", "针扎一样", "越来越痛", "好几周了",
    ])
    func concerning(_ text: String) {
        #expect(SafetyScreener.screen(text) == .concerning)
    }

    @Test(arguments: [
        "give me exercises that can ease my lower back pain", "tight hamstrings",
        "dolor de espalda baja", "", "🙂", "give me a number of hip stretches",
        "my fellow runner said try this", "sharpen my focus with breathing",
        "breaststroke drills", "quiero un empire state tour",
        "help with falling asleep", "trouble sleeping", "太麻烦了",
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
        #expect(PhraseMatcher.normalize("douleur à la poitrine") == PhraseMatcher.normalize("douleur a la poitrine"))
        #expect(PhraseMatcher.normalize("can’t") == "can't")
        #expect(PhraseMatcher.normalize("  A   B\n") == "a b")
    }
}
