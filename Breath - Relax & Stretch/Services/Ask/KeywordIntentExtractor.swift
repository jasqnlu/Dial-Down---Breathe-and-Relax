import Foundation

/// No-AI fallback: turns a sentence into body areas, a goal and minutes by matching
/// synonym tables (English, Spanish, French, Simplified Chinese) over normalized text.
/// Latin phrases match on word boundaries ("back" never matches "backpack"; a trailing
/// "*" marks a stem that may continue into a longer word). CJK phrases match as substrings.
/// The keyword path cannot judge safety or relevance: `seriousness` is `.ok`, `isOffTopic`
/// is `false`, and an empty intent means "ask the user to clarify".
nonisolated struct KeywordIntentExtractor: nonisolated IntentExtractor {
    func extract(_ text: String) async throws -> AskIntent {
        intent(for: text)
    }

    func intent(for text: String) -> AskIntent {
        var working = Self.boundaryForm(SafetyScreener.normalize(text))

        let minutes = Self.minutes(in: &working)

        // Longest phrase first; matched text is blanked so shorter synonyms can't re-match it.
        var areas: [AskArea] = []
        for (phrase, area) in Self.areaPhrases where phrase.blankFirstMatch(in: &working) {
            if !areas.contains(area) { areas.append(area) }
        }

        let goal = Self.goalTable.first { _, phrases in
            phrases.contains { $0.matches(working) }
        }?.0

        return AskIntent(areas: areas, goal: goal, minutes: minutes,
                         seriousness: .ok, isOffTopic: false)
    }

    // MARK: - Matching

    private struct Phrase {
        let text: String
        let isStem: Bool
        let isCJK: Bool

        init(_ source: String) {
            isStem = source.hasSuffix("*")
            let raw = isStem ? String(source.dropLast()) : source
            text = KeywordIntentExtractor.boundaryForm(SafetyScreener.normalize(raw))
                .trimmingCharacters(in: .whitespaces)
            isCJK = text.unicodeScalars.contains { $0.value >= 0x2E80 }
        }

        private var needle: String {
            isCJK ? text : " " + text + (isStem ? "" : " ")
        }

        func matches(_ haystack: String) -> Bool { haystack.contains(needle) }

        /// Replaces the first match with spaces (keeping neighbouring boundary spaces).
        func blankFirstMatch(in haystack: inout String) -> Bool {
            guard let found = haystack.range(of: needle) else { return false }
            var inner = found
            if !isCJK {
                inner = haystack.index(after: found.lowerBound)..<(isStem ? found.upperBound
                                                                   : haystack.index(before: found.upperBound))
            }
            haystack.replaceSubrange(inner, with: String(repeating: " ", count: haystack[inner].count))
            return true
        }
    }

    /// Non-letter/digit characters become spaces; padded so Latin phrases match whole words.
    private static func boundaryForm(_ normalized: String) -> String {
        let mapped = String(normalized.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        })
        return " " + mapped.split(separator: " ").joined(separator: " ") + " "
    }

    // MARK: - Minutes

    private static let minutesPattern = try! Regex(#"(\d{1,3}) ?(?:min\w*|分钟)"#)
    private static let quickPhrases = ["quick*", "rapid*", "快速"].map { Phrase($0) }

    /// Reads (and blanks, so "dos minutos" can't look like a body part) the duration.
    private static func minutes(in working: inout String) -> Int? {
        if let match = working.firstMatch(of: minutesPattern) {
            let value = match.output[1].substring.flatMap { Int($0) }
            let range = match.range
            working.replaceSubrange(range, with: String(repeating: " ", count: working[range].count))
            if let value, value > 0 { return value }
        }
        return quickPhrases.contains { $0.matches(working) } ? 3 : nil
    }

    // MARK: - Tables (data, not branching code)

    private static let areaPhrases: [(Phrase, AskArea)] = areaSynonyms
        .flatMap { area, words in words.map { (Phrase($0), area) } }
        .sorted { $0.0.text.count > $1.0.text.count }

    // Bare "back" means lower back. Sides (left/right/izquierd*/derech*/gauche/droit/左/右) are never listed.
    private static let areaSynonyms: [(AskArea, [String])] = [
        (.lowerBack, [
            "lower back", "low back", "lumbar", "lumbar spine", "back", "spine",
            "espalda baja", "zona lumbar", "parte baja de la espalda", "lumbares", "espalda", "columna",
            "bas du dos", "bas de dos", "lombaires", "lombalgie", "mal au dos", "le dos", "du dos", "mon dos", "au dos", "colonne",
            "腰", "下背", "下背部", "腰部", "背", "脊柱"]),
        (.upperBack, [
            "upper back", "mid back", "middle back", "trapezius", "traps", "between my shoulder blades",
            "espalda alta", "parte alta de la espalda", "espalda media", "trapecio*", "dorsal*",
            "haut du dos", "milieu du dos", "trapeze*", "omoplate*",
            "上背", "上背部", "中背", "斜方肌", "肩胛"]),
        (.neck, [
            "neck", "cervical",
            "cuello", "cervical*", "cervicales",
            "cou", "nuque", "cervicales",
            "脖子", "颈", "颈部", "颈椎"]),
        (.shoulders, [
            "shoulder*", "deltoid*",
            "hombro*", "deltoides",
            "epaule*", "deltoide*",
            "肩", "肩膀", "肩部"]),
        (.head, [
            "head", "headache*", "temple*", "forehead", "migraine*",
            "cabeza", "dolor de cabeza", "sien*", "frente", "migrana*",
            "tete", "mal de tete", "tempe*", "migraine*",
            "头", "头部", "头痛", "太阳穴", "额头", "偏头痛"]),
        (.jaw, [
            "jaw", "tmj", "clench*", "teeth grinding", "mandibula", "mandibul*", "bruxismo",
            "machoire", "bruxisme", "serrer les dents",
            "下巴", "下颌", "颌", "磨牙"]),
        (.eyes, [
            "eye", "eyes", "eyestrain", "eye strain", "screen fatigue",
            "ojo*", "vista cansada", "fatiga visual",
            "oeil", "yeux", "fatigue oculaire",
            "眼睛", "眼", "用眼", "视疲劳"]),
        (.chest, [
            "chest", "pecs", "pectoral*",
            "pecho", "pectoral*",
            "poitrine", "pectoraux",
            "胸", "胸部", "胸肌"]),
        (.core, [
            "core", "abs", "abdominal*", "stomach", "belly", "tummy",
            "abdomen", "abdominal*", "estomago", "barriga", "vientre", "panza",
            "abdominaux", "ventre", "estomac",
            "核心", "腹部", "腹", "肚子", "小腹"]),
        (.obliques, [
            "oblique*", "side of my waist", "love handles", "waist", "side stretch",
            "oblicuo*", "cintura", "costado",
            "obliques", "taille", "flanc*",
            "腰侧", "侧腰", "腹斜肌"]),
        (.lats, [
            "lats", "latissimus", "side of my back",
            "dorsales", "dorsal ancho", "latissimus dorsi", "grand dorsal", "grands dorsaux",
            "背阔肌"]),
        (.biceps, [
            "bicep*", "upper arm*", "arm", "arms",
            "biceps", "brazo*", "bras",
            "二头肌", "上臂", "手臂", "胳膊"]),
        (.triceps, [
            "tricep*",
            "triceps",
            "三头肌", "手臂后侧"]),
        (.forearms, [
            "forearm*", "wrist*", "elbow*", "typing", "carpal tunnel",
            "antebrazo*", "muneca*", "codo*", "tunel carpiano",
            "avant-bras", "poignet*", "coude*", "canal carpien",
            "前臂", "手腕", "手肘", "肘", "腕管"]),
        (.hands, [
            "hand", "hands", "finger*", "palm*", "thumb*",
            "mano*", "dedo*", "palma*", "pulgar*",
            "main", "mains", "doigt*", "paume*", "pouce*",
            "手", "手指", "手掌", "拇指"]),
        (.glutes, [
            "glute*", "butt", "buttock*", "piriformis", "sciatica",
            "gluteo*", "nalga*", "gluteos", "piramidal", "ciatica",
            "fessier*", "fesses", "piriforme", "sciatique",
            "臀", "臀部", "臀肌", "梨状肌", "坐骨神经"]),
        (.hipFlexors, [
            "hip flexor*", "psoas", "iliopsoas", "front of my hip*",
            "flexor* de la cadera", "flexores de cadera", "psoas iliaco",
            "fléchisseur* de la hanche", "flechisseur*", "psoas",
            "髋屈肌", "髂腰肌", "髋前侧"]),
        (.hips, [
            "hip", "hips",
            "cadera*",
            "hanche*",
            "髋", "髋部", "胯", "髋关节"]),
        (.adductors, [
            "adductor*", "inner thigh*", "groin",
            "aductor*", "muslo interno", "muslos internos", "interior del muslo", "ingle*",
            "adducteur*", "interieur des cuisses", "cuisse interne", "aine*",
            "内收肌", "大腿内侧", "腹股沟"]),
        (.quads, [
            "quad*", "thigh*", "front of my thigh*", "front of my leg*",
            "cuadricep*", "muslo*", "frente del muslo",
            "cuisse*", "quadriceps",
            "股四头肌", "大腿", "大腿前侧"]),
        (.hamstrings, [
            "hamstring*", "back of my thigh*", "back of my leg*",
            "isquiotibial*", "isquios", "femorales", "parte trasera del muslo",
            "ischio-jambier*", "ischio jambier*", "ischios", "arriere des cuisses", "arriere de la cuisse",
            "腘绳肌", "大腿后侧", "大腿后面"]),
        (.calves, [
            "calf", "calves", "gastrocnemius", "soleus",
            "pantorrilla*", "gemelo*", "sóleo", "soleo",
            "mollet*",
            "小腿", "腓肠肌", "小腿肚"]),
        (.shins, [
            "shin*", "tibialis",
            "espinilla*", "tibial*", "canilla*",
            "tibia*",
            "胫骨", "胫前肌", "小腿前侧"]),
        (.feet, [
            "foot", "feet", "ankle*", "heel*", "arch of my foot", "plantar", "toes",
            "pie", "pies", "tobillo*", "talon*", "talones", "planta del pie", "dedos del pie", "fascitis plantar",
            "pied", "pieds", "cheville*", "talon*", "voute plantaire", "orteil*",
            "脚", "足", "足部", "脚踝", "脚跟", "脚底", "足底", "脚趾"]),
    ]

    /// Checked in priority order: pain beats tight, stress beats sleep, and so on.
    private static let goalTable: [(AskGoal, [Phrase])] = goalSynonyms
        .map { goal, words in (goal, words.map { Phrase($0) }) }

    private static let goalSynonyms: [(AskGoal, [String])] = [
        (.pain_relief, [
            "pain", "pains", "painful", "sore", "soreness", "ache", "aches", "aching", "hurt", "hurts", "hurting",
            "dolor*", "duele*", "adolorid*", "molestia*", "dolorid*",
            "mal", "douleur*", "douloureu*", "courbature*", "fait mal",
            "疼", "痛", "酸", "酸痛", "不舒服"]),
        (.stress_relief, [
            "stress*", "anxious", "anxiety", "nervous", "overwhelmed", "calm down", "tense",
            "estres*", "ansios*", "ansiedad", "nervios*", "agobiad*", "calmarme", "tenso", "tensa",
            "anxieu*", "anxiete", "angoiss*", "nerveu*", "tendu*", "tendue*", "calmer", "stresse*",
            "压力", "焦虑", "紧张", "烦躁", "平静"]),
        (.unwind, [
            "sleep*", "wind down", "unwind", "bedtime", "before bed", "insomnia", "relax*", "night",
            "dormir", "sueno", "antes de acostarme", "relajar*", "insomnio", "noche", "descansar",
            "sommeil", "me detendre", "avant de dormir", "coucher", "insomnie", "detend*", "nuit",
            "睡", "睡觉", "睡眠", "失眠", "放松", "睡前", "晚上"]),
        (.wake_up, [
            "wake up", "wake me up", "morning", "energize", "energy", "energise", "get going", "sluggish",
            "despertar*", "despierto", "manana", "energia", "energizar", "activar*",
            "reveil*", "matin", "energie", "energiser", "me reveiller",
            "醒", "起床", "早上", "早晨", "提神", "精神"]),
        (.better_breathing, [
            "breath*", "lungs", "diaphragm",
            "respir*", "pulmon*", "aliento", "diafragma",
            "respire*", "poumon*", "souffle", "diaphragme",
            "呼吸", "深呼吸", "肺", "横膈膜"]),
        (.flexibility, [
            "flexib*", "tight*", "stiff*", "mobility", "loosen*", "stretch out", "limber",
            "flexibilidad", "flexible*", "rigid*", "tens*", "agarrotad*", "movilidad", "soltar", "estirar",
            "souple*", "souplesse", "raide*", "mobilite", "assouplir", "etirement*", "bloque*",
            "灵活", "柔韧", "僵", "僵硬", "紧绷", "拉伸", "活动度"]),
    ]
}
