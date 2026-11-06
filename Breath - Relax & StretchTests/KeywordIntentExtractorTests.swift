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

    // MARK: - Review fixes

    @Test(arguments: [
        ("me siento tenso", [AskArea]()),
        ("dolor de cuello frente al ordenador", [.neck]),
        ("my main issue is my neck", [.neck]),
        ("estoy de pie todo el día y me duele la espalda", [.lowerBack]),
        ("I love apple pie", []),
        ("睡眠不足", []),
        ("玩手机太久", []),
        ("背包很重", []),
        ("腰疼", [.lowerBack]),
        ("back of my neck", [.neck]),
        ("back of the neck", [.neck]),
        ("back of my head", [.head]),
        ("back of the knee", [.hamstrings]),
        ("back of the thigh", [.hamstrings]),
        ("behind my thigh", [.hamstrings]),
        ("me duele detrás del muslo", [.hamstrings]),
        ("parte de atrás del muslo", [.hamstrings]),
        ("derrière de la cuisse", [.hamstrings]),
        ("arrière de la cuisse", [.hamstrings]),
        ("flexores de la cadera", [.hipFlexors]),
        ("fléchisseurs de la hanche", [.hipFlexors]),
        ("mal de dos", [.lowerBack]),
        ("hace dos días me duele el cuello", [.neck]),
        ("hace dos dias me duele el cuello", [.neck]),
        ("dos minutos para el cuello", [.neck]),
        ("tengo dolor de pie", [.feet]),
        ("mes mains sont fatiguées", [.hands]),
        ("手腕疼", [.forearms]),
    ])
    func noCrossLanguageCollisions(_ text: String, _ expected: [AskArea]) {
        #expect(extractor.intent(for: text).areas == expected)
    }

    @Test(arguments: [
        ("j'ai mal au dos", AskArea.lowerBack),
        ("dolor de cabeza", .head),
        ("头痛", .head),
        ("mal de dos", .lowerBack),
    ])
    func painWordSurvivesAreaPhrase(_ text: String, _ area: AskArea) {
        let i = extractor.intent(for: text)
        #expect(i.areas == [area])
        #expect(i.goal == .pain_relief)
    }

    @Test(arguments: ["I have a headache", "migraine", "sciatica", "lombalgie"])
    func painConditionsCarryPain(_ text: String) {
        #expect(extractor.intent(for: text).goal == .pain_relief)
    }

    @Test func malIsNotAlwaysPain() {
        #expect(extractor.intent(for: "duermo mal").goal == .unwind)
        #expect(extractor.intent(for: "duermo mal a menudo").goal == .unwind)
        #expect(extractor.intent(for: "j'ai mal à la tête").goal == .pain_relief)
        #expect(extractor.intent(for: "pas mal de stress").goal == .stress_relief)
    }

    @Test func muscleTensionIsFlexibilityNotRelaxation() {
        #expect(extractor.intent(for: "tense neck").goal == .flexibility)
        #expect(extractor.intent(for: "relax my shoulders").goal == nil)
    }

    @Test func minutesNeedAMinuteWord() {
        #expect(extractor.intent(for: "5 minimal neck").minutes == nil)
        #expect(extractor.intent(for: "4 mind neck").minutes == nil)
        #expect(extractor.intent(for: "1.5 minutes neck").minutes == nil)
        #expect(extractor.intent(for: "10mins neck").minutes == 10)
        #expect(extractor.intent(for: "dos minutos para el cuello").minutes == 2)
    }

    // MARK: - Exercise count (live mini routine)

    @Test(arguments: [
        ("3 exercises for my neck", 3),
        ("three stretches for my hips", 3),
        ("one breathing exercise", 1),
        ("a couple of really gentle hip stretches", 2),
        ("give me a few stretches for my back", 3),
        ("2 more for my hips", 2),
        ("one more neck stretch", 1),
        ("2 for my shoulders", 2),
        ("add 4 for my calves", 4),
        ("another one", 1),
        ("another neck stretch", 1),
        ("tres ejercicios para el cuello", 3),
        ("dos estiramientos para la espalda", 2),
        ("trois étirements pour le cou", 3),
        ("deux exercices pour le dos", 2),
        ("三个拉伸动作", 3),
        ("3个脖子的动作", 3),
    ])
    func exerciseCount(_ text: String, _ expected: Int) {
        #expect(extractor.intent(for: text).count == expected)
    }

    @Test(arguments: [
        "my neck is tight",
        "5 minute neck stretch",
        "3 minute neck stretches",
        "mal de dos",
        "hace dos días me duele el cuello",
    ])
    func noExerciseCount(_ text: String) {
        #expect(extractor.intent(for: text).count == nil)
    }

    @Test func countAndMinutesTogether() {
        let i = extractor.intent(for: "three exercises in 3 minutes for my neck")
        #expect(i.count == 3)
        #expect(i.minutes == 3)
        #expect(i.areas == [.neck])
    }

    @Test func countWordIsNotAnArea() {
        // French "dos" (back) must survive as an area when Spanish "dos" isn't a count.
        let i = extractor.intent(for: "deux exercices pour le dos")
        #expect(i.areas == [.lowerBack])
    }

    @Test func countIsClampedToTen() {
        #expect(extractor.intent(for: "50 exercises for my neck").count == 10)
    }

    // MARK: - Explicit "new routine" (default is to add to the current one)

    @Test(arguments: [
        "create a new routine for my lower back",
        "make a new one with 3 hip stretches",
        "start over",
        "let's start fresh with my neck",
        "do calves instead",
        "nueva rutina para las caderas",
        "empezar de nuevo",
        "une nouvelle routine pour le cou",
        "recommencer",
        "重新开始",
        "换一套脖子的动作",
    ])
    func wantsNewRoutine(_ text: String) {
        #expect(extractor.intent(for: text).wantsNewRoutine)
    }

    @Test(arguments: [
        "3 exercises for my neck",
        "add 2 more for my hips",
        "another one",
        "tight hips",
        "my new job gives me neck pain",
    ])
    func addsByDefault(_ text: String) {
        #expect(extractor.intent(for: text).wantsNewRoutine == false)
    }

    // MARK: - Edits to the routine being built

    @Test(arguments: [
        ("remove the last one", AskEdit.remove),
        ("delete the neck ones", .remove),
        ("remove 2 exercises", .remove),
        ("take out the hip stretch", .remove),
        ("swap the last one", .swap),
        ("give me a different one", .swap),
        ("replace the neck one", .swap),
        ("make it shorter", .shorter),
        ("make it longer", .longer),
        ("quita el último", .remove),
        ("cambia el último", .swap),
        ("hazlo más corto", .shorter),
        ("enlève le dernier", .remove),
        ("remplace le dernier", .swap),
        ("plus long", .longer),
        ("删掉最后一个", .remove),
        ("换一个", .swap),
        ("短一点", .shorter),
    ])
    func edits(_ text: String, _ expected: AskEdit) {
        #expect(extractor.intent(for: text).edit == expected)
    }

    @Test(arguments: ["3 exercises for my neck", "tight hips", "start over", "add 2 more for my hips"])
    func noEdit(_ text: String) {
        #expect(extractor.intent(for: text).edit == nil)
    }

    @Test func aDifferentOneSwapsRatherThanStartingOver() {
        #expect(extractor.intent(for: "give me a different one").wantsNewRoutine == false)
    }

    @Test func removeKeepsItsAreaAndCount() {
        let byArea = extractor.intent(for: "delete the neck ones")
        #expect(byArea.areas == [.neck])
        #expect(extractor.intent(for: "remove 2 exercises").count == 2)
    }

    @Test func newRoutinePhraseIsNotACount() {
        let i = extractor.intent(for: "make a new one with 3 hip stretches")
        #expect(i.count == 3)
        #expect(i.areas == [.hips])
    }
}
