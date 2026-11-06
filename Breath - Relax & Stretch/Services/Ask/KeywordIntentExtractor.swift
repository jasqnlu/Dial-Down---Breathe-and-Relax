import Foundation

/// No-AI fallback: turns a sentence into body areas, a goal and minutes by matching
/// synonym tables (English, Spanish, French, Simplified Chinese) over normalized text.
/// Phrase rules (word boundaries, "*" stems, CJK substrings) live in `PhraseMatcher`.
/// The keyword path cannot judge safety or relevance: `seriousness` is `.ok`, `isOffTopic`
/// is `false`, and an empty intent means "ask the user to clarify".
nonisolated struct KeywordIntentExtractor: nonisolated IntentExtractor {
    func extract(_ text: String) async throws -> AskIntent {
        intent(for: text)
    }

    func intent(for text: String) -> AskIntent {
        // "1.5" -> "1d5" so a decimal can never be read as a whole number of minutes.
        let normalized = PhraseMatcher.normalize(text)
            .replacing(/(\d)[.,](\d)/) { "\($0.1)d\($0.2)" }
        var working = PhraseMatcher.boundaryForm(normalized)

        let minutes = Self.minutes(in: &working)
        let edit = Self.editTable.first { _, phrases in
            phrases.contains { $0.blankFirstMatch(in: &working) }
        }?.0
        // "New routine" phrases are blanked before counting, so "a new one" is never "1 exercise".
        let wantsNewRoutine = Self.newRoutinePhrases.reduce(false) { found, phrase in
            phrase.blankFirstMatch(in: &working) || found
        }
        let count = Self.count(in: &working)

        // The goal is read before area phrases are blanked, so "mal au dos" and
        // "dolor de cabeza" keep their pain word.
        var goalText = working
        for phrase in Self.goalNeutralPhrases { _ = phrase.blankFirstMatch(in: &goalText) }
        let goal = Self.goalTable.first { _, phrases in
            phrases.contains { $0.matches(goalText) }
        }?.0

        // Longest phrase first; matched text is blanked so shorter synonyms can't re-match it.
        var areas: [AskArea] = []
        for (phrase, area) in Self.areaPhrases where phrase.blankFirstMatch(in: &working) {
            if !areas.contains(area) { areas.append(area) }
        }

        return AskIntent(areas: areas, goal: goal, minutes: minutes,
                         seriousness: .ok, isOffTopic: false,
                         count: count, wantsNewRoutine: wantsNewRoutine, edit: edit)
    }

    // MARK: - Edits to the routine being built

    /// Checked in order; the first edit found wins.
    private static let editTable: [(AskEdit, [PhraseMatcher])] = [
        (.remove, [
            "remove", "delete", "drop", "take out", "get rid of",
            "quita", "quitar", "quitame", "elimina", "eliminar", "saca", "borra",
            "enleve", "enlever", "supprime", "supprimer", "retire", "retirer",
            "删掉", "删除", "去掉", "拿掉"]),
        (.swap, [
            "swap", "replace", "switch out", "different one", "something else",
            "cambia", "cambiar", "reemplaza", "reemplazar",
            "remplace", "remplacer", "change", "changer",
            "换一个", "替换", "换掉"]),
        (.shorter, [
            "shorter", "quicker", "less time",
            "mas corto", "mas corta", "menos tiempo",
            "plus court", "plus courte", "moins de temps",
            "短一点", "缩短"]),
        (.longer, [
            "longer", "more time",
            "mas largo", "mas larga", "mas tiempo",
            "plus long", "plus longue", "plus de temps",
            "长一点", "延长"]),
    ].map { edit, words in (edit, words.map { PhraseMatcher($0) }) }

    // MARK: - Exercise count

    private static let countWords: [String: Int] = numberWords.merging([
        "a couple of": 2, "couple of": 2, "a few": 3, "few": 3, "un par de": 2, "quelques": 3,
    ]) { current, _ in current }

    /// Latin number tokens, longest first so "a couple of" wins over "couple of".
    private static let latinNumber: String = {
        let words = countWords.keys
            .filter { !$0.unicodeScalars.contains { $0.value >= 0x2E80 } }
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
        return "(\\d{1,3}|" + words.joined(separator: "|") + ")"
    }()
    private static let cjkNumber = "(\\d{1,2}|[一二两三四五六七八九十]{1,2})"

    private static let countNouns = [
        "exercises?", "stretch(?:es)?", "moves?", "poses?", "ones",
        "ejercicios?", "estiramientos?", "movimientos?", "posturas?",
        "exercices?", "etirements?", "mouvements?", "postures?",
    ].joined(separator: "|")

    /// Each pattern's group 1 is the number token (blanked once read). A nil group means the
    /// pattern itself stands for one exercise ("another one").
    private static let countPatterns: [(Regex<AnyRegexOutput>, fixed: Int?)] = [
        // "3 exercises", "a couple of really gentle hip stretches" (up to 3 words in between),
        // but not "30 seconds per stretch".
        (try! Regex(" \(latinNumber)(?! (?:secs?|seconds?|segundos?|secondes?) )(?: [a-z]+){0,3}? (?:\(countNouns)) "), nil),
        // "2 more", "one more neck stretch"
        (try! Regex(" \(latinNumber) more "), nil),
        // "2 for my shoulders", "add 4 for my calves"
        (try! Regex("(?:^| add| give me| do| dame| ajoute) \(latinNumber) (?:for|of|on|to|para|pour) "), nil),
        // "三个拉伸动作", "3个脖子的动作"
        (try! Regex("\(cjkNumber)个?[^ ]{0,6}?(?:动作|练习|拉伸|伸展)"), nil),
        // "another one", "another neck stretch"
        (try! Regex(" another(?: [a-z]+){0,2} (?:\(countNouns)|one) "), 1),
    ]

    /// Reads (and blanks the number of) "N exercises" and its variants, clamped to 1...10.
    private static func count(in working: inout String) -> Int? {
        for (pattern, fixed) in countPatterns {
            guard let match = working.firstMatch(of: pattern) else { continue }
            if let fixed { return fixed }
            guard let token = match.output[1].substring, let range = match.output[1].range else { continue }
            working.replaceSubrange(range, with: String(repeating: " ", count: token.count))
            guard let value = Int(token) ?? countWords[String(token)], value > 0 else { return nil }
            return min(value, AskIntent.maxCount)
        }
        return nil
    }

    /// Only explicit wording replaces the routine; every other request adds to it.
    private static let newRoutinePhrases = [
        "start over", "start again", "start fresh", "from scratch", "new routine", "new one",
        "different routine", "fresh routine", "instead",
        "nueva rutina", "rutina nueva", "otra rutina", "rutina diferente", "empezar de nuevo",
        "empecemos de nuevo", "desde cero", "en su lugar", "en lugar de eso",
        "nouvelle routine", "autre routine", "routine differente", "recommencer", "on recommence",
        "a zero", "depuis le debut", "a la place",
        "重新开始", "重新来", "从头开始", "换一套", "新的一套", "换成",
    ].map { PhraseMatcher($0) }

    // MARK: - Minutes

    /// Whole numbers only: "1.5 minutes" yields nil. Number words let "dos minutos" count as
    /// a duration (and keeps "dos" from being read as the French word for back).
    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "fifteen": 15, "twenty": 20,
        "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8,
        "nueve": 9, "diez": 10, "quince": 15, "veinte": 20,
        "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "sept": 7, "huit": 8, "neuf": 9,
        "dix": 10, "quinze": 15, "vingt": 20,
        "一": 1, "两": 2, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
        "十": 10, "十五": 15, "二十": 20, "三十": 30,
    ]

    private static let minutesPattern: Regex<AnyRegexOutput> = {
        let words = numberWords.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        return try! Regex("(?:^|[^\\da-z])(\\d{1,3}|\(words)) ?(?:(?:mins?|minutes?|minutos?)\\b|分钟)")
    }()
    private static let quickPhrases = ["quick*", "rapid*", "快速"].map { PhraseMatcher($0) }

    /// Reads (and blanks) the duration so it can't be mistaken for a body part.
    private static func minutes(in working: inout String) -> Int? {
        if let match = working.firstMatch(of: minutesPattern) {
            let token = String(match.output[1].substring ?? "")
            let range = (match.output[1].range ?? match.range).lowerBound..<match.range.upperBound
            working.replaceSubrange(range, with: String(repeating: " ", count: working[range].count))
            if let value = Int(token) ?? numberWords[token], value > 0 { return value }
        }
        return quickPhrases.contains { $0.matches(working) } ? 3 : nil
    }

    // MARK: - Tables (data, not branching code)
    // A trailing "*" is a stem; never put "*" mid-phrase. Avoid bare words that are common in
    // another supported language (es "pie", fr "main", es "frente", es "sien" as a stem) and
    // bare single CJK characters that occur inside unrelated words (足, 手, 背).

    private static let areaPhrases: [(PhraseMatcher, AskArea)] = areaSynonyms
        .flatMap { area, words in words.map { (PhraseMatcher($0), area) } }
        .sorted { $0.0.text.count > $1.0.text.count }

    // Bare "back" means lower back. Sides (left/right/izquierd*/derech*/gauche/droit/左/右) are never listed.
    private static let areaSynonyms: [(AskArea, [String])] = [
        (.lowerBack, [
            "lower back", "low back", "lumbar", "lumbar spine", "back", "spine",
            "espalda baja", "zona lumbar", "parte baja de la espalda", "lumbares", "espalda", "columna",
            "bas du dos", "bas de dos", "lombaires", "lombalgie", "mal de dos", "mal au dos", "le dos", "du dos", "mon dos", "au dos", "ton dos", "colonne",
            "腰", "下背", "下背部", "腰部", "后背", "背部", "脊柱"]),
        (.upperBack, [
            "upper back", "mid back", "middle back", "trapezius", "traps", "between my shoulder blades",
            "espalda alta", "parte alta de la espalda", "espalda media", "trapecio*", "dorsal*",
            "haut du dos", "milieu du dos", "trapeze*", "omoplate*",
            "上背", "上背部", "中背", "斜方肌", "肩胛"]),
        (.neck, [
            "neck", "back of my neck", "back of the neck", "back of neck", "cervical*",
            "cuello", "cervicales", "cou", "nuque",
            "脖子", "颈", "颈部", "颈椎"]),
        (.shoulders, [
            "shoulder*", "deltoid*",
            "hombro*", "epaule*",
            "肩", "肩膀", "肩部"]),
        (.head, [
            "head", "back of my head", "back of the head", "headache*", "temples", "temple", "forehead", "migraine*",
            "cabeza", "dolor de cabeza", "sien", "sienes", "la frente", "mi frente", "migrana*",
            "tete", "mal de tete", "tempe", "tempes",
            "头部", "头疼", "头痛", "太阳穴", "额头", "偏头痛"]),
        (.jaw, [
            "jaw", "tmj", "clench*", "teeth grinding", "mandibul*", "bruxismo",
            "machoire", "bruxisme", "serrer les dents",
            "下巴", "下颌", "磨牙", "颌骨"]),
        (.eyes, [
            "eye", "eyes", "eyestrain", "eye strain", "screen fatigue",
            "ojo", "ojos", "vista cansada", "fatiga visual",
            "oeil", "yeux", "fatigue oculaire",
            "眼睛", "眼部", "用眼", "视疲劳"]),
        (.chest, [
            "chest", "pecs", "pectoral*",
            "pecho", "poitrine", "pectoraux",
            "胸部", "胸口", "胸肌"]),
        (.core, [
            "core", "abs", "abdominal*", "stomach", "belly", "tummy",
            "abdomen", "estomago", "barriga", "vientre", "panza",
            "abdominaux", "ventre", "estomac",
            "核心", "腹部", "肚子", "小腹"]),
        (.obliques, [
            "oblique*", "side of my waist", "love handles", "waist", "side stretch",
            "oblicuo*", "cintura", "costado",
            "taille", "flanc*",
            "腰侧", "侧腰", "腹斜肌"]),
        (.lats, [
            "lats", "latissimus", "side of my back",
            "dorsales", "dorsal ancho", "grand dorsal", "grands dorsaux",
            "背阔肌"]),
        (.biceps, [
            "bicep*", "upper arm*", "arm", "arms",
            "brazo*", "mon bras", "mes bras", "le bras", "les bras",
            "二头肌", "上臂", "手臂", "胳膊"]),
        (.triceps, [
            "tricep*",
            "三头肌", "手臂后侧"]),
        (.forearms, [
            "forearm*", "wrist*", "elbow*", "typing", "carpal tunnel",
            "antebrazo*", "muneca*", "codo*", "tunel carpiano",
            "avant-bras", "poignet*", "coude*", "canal carpien",
            "前臂", "手腕", "手肘", "腕管"]),
        (.hands, [
            "hand", "hands", "finger*", "palm", "palms", "thumb*",
            "mano", "manos", "dedo", "dedos", "palma", "palmas", "pulgar*",
            "mes mains", "les mains", "ma main", "mon doigt", "mes doigts", "doigt", "doigts", "paume*", "pouce*",
            "手部", "手指", "手掌", "拇指"]),
        (.glutes, [
            "glute*", "butt", "buttock*", "piriformis", "sciatica",
            "gluteo*", "nalga*", "ciatica", "piriforme",
            "fessier*", "fesses", "sciatique",
            "臀", "臀部", "臀肌", "梨状肌", "坐骨神经"]),
        (.hipFlexors, [
            "hip flexor*", "psoas", "iliopsoas", "front of my hip*",
            "flexores de la cadera", "flexores de cadera", "psoas iliaco",
            "flechisseur*", "flechisseurs de la hanche", "flechisseur de la hanche",
            "髋屈肌", "髂腰肌", "髋前侧"]),
        (.hips, [
            "hip", "hips",
            "cadera*",
            "hanche*",
            "髋", "髋部", "胯", "髋关节"]),
        (.adductors, [
            "adductor*", "inner thigh*", "groin",
            "aductor*", "muslo interno", "muslos internos", "interior del muslo", "ingle", "ingles",
            "adducteur*", "interieur des cuisses", "cuisse interne", "aine", "aines",
            "内收肌", "大腿内侧", "腹股沟"]),
        (.quads, [
            "quad*", "thigh*", "front of my thigh*", "front of my leg*",
            "cuadricep*", "muslo*", "frente del muslo",
            "cuisse*",
            "股四头肌", "大腿", "大腿前侧"]),
        (.hamstrings, [
            "hamstring*", "back of my thigh*", "back of the thigh*", "behind my thigh*", "behind the thigh*",
            "back of my leg*", "back of the leg*", "back of my knee", "back of the knee",
            "behind my knee", "behind the knee",
            "isquiotibial*", "isquios", "femorales", "parte trasera del muslo", "parte de atras del muslo",
            "parte de atras de los muslos", "detras del muslo", "detras de los muslos", "detras de la rodilla",
            "ischio jambier*", "ischios", "arriere des cuisses", "arriere de la cuisse",
            "derriere de la cuisse", "derriere des cuisses", "derriere le genou",
            "腘绳肌", "大腿后侧", "大腿后面"]),
        (.calves, [
            "calf", "calves", "gastrocnemius", "soleus",
            "pantorrilla*", "gemelo*", "soleo",
            "mollet*",
            "小腿", "腓肠肌", "小腿肚"]),
        (.shins, [
            "shin", "shins", "tibial*",
            "espinilla*", "canilla*", "tibia", "tibias",
            "胫骨", "胫前肌", "小腿前侧"]),
        (.feet, [
            "foot", "feet", "ankle*", "heel*", "arch of my foot", "plantar", "toe", "toes",
            "dolor de pie", "dolor de pies", "los pies", "mis pies", "mi pie",
            "tobillo*", "talon*", "planta del pie", "dedos del pie",
            "au pied", "aux pieds", "les pieds", "mes pieds", "mon pied", "cheville*", "voute plantaire", "orteil*",
            "脚", "足部", "足底", "脚踝", "脚跟", "脚底", "脚趾"]),
    ]

    /// Phrases that look like goal words but aren't ("pas mal de stress" = a lot of stress).
    private static let goalNeutralPhrases = ["pas mal"].map { PhraseMatcher($0) }

    /// Checked in priority order: pain beats tight, stress beats sleep, and so on.
    /// Bare "mal" is not a pain word ("duermo mal", "mal a menudo"); only "mal de/au/aux", "mal a la/l/mon/ma/mes" and "fait mal" are.
    private static let goalTable: [(AskGoal, [PhraseMatcher])] = goalSynonyms
        .map { goal, words in (goal, words.map { PhraseMatcher($0) }) }

    private static let goalSynonyms: [(AskGoal, [String])] = [
        (.pain_relief, [
            "pain", "pains", "painful", "sore", "soreness", "ache", "aches", "aching", "hurt", "hurts", "hurting",
            "headache*", "migraine*", "sciatica",
            "dolor*", "duele*", "duelen", "adolorid*", "molestia*", "dolorid*", "migrana*", "ciatica", "lumbalgia",
            "mal de", "mal au", "mal aux", "mal a la", "mal a l", "mal a mon", "mal a ma", "mal a mes", "fait mal", "douleur*", "douloureu*", "courbature*",
            "lombalgie", "sciatique",
            "疼", "痛", "酸", "不舒服"]),
        (.stress_relief, [
            "stress*", "anxious", "anxiety", "nervous", "overwhelmed", "calm down",
            "estres*", "ansios*", "ansiedad", "nervios*", "agobiad*", "calmarme",
            "anxieu*", "anxiete", "angoiss*", "nerveu*", "calmer",
            "压力", "焦虑", "紧张", "烦躁", "平静"]),
        (.unwind, [
            "sleep*", "wind down", "unwind", "bedtime", "before bed", "insomnia", "night",
            "dormir", "duermo", "duermes", "dormi", "sueno", "antes de acostarme", "insomnio", "noche", "descansar",
            "sommeil", "avant de dormir", "coucher", "insomnie", "nuit",
            "睡", "失眠", "晚上"]),
        (.wake_up, [
            "wake up", "wake me up", "morning", "energize", "energy", "energise", "get going", "sluggish",
            "despertar*", "despierto", "manana", "energia", "energizar", "activar*",
            "reveil*", "matin", "energie", "energiser", "me reveiller",
            "醒", "起床", "早上", "早晨", "提神", "精神"]),
        (.better_breathing, [
            "breath*", "lungs", "diaphragm",
            "respir*", "pulmon*", "aliento", "diafragma",
            "poumon*", "souffle", "diaphragme",
            "呼吸", "肺部", "横膈膜"]),
        (.flexibility, [
            "flexib*", "tight*", "stiff*", "tense", "tension*", "mobility", "loosen*", "stretch out", "limber",
            "rigid*", "tenso", "tensa", "agarrotad*", "movilidad", "soltar", "estirar",
            "souple*", "souplesse", "raide*", "mobilite", "assouplir", "etirement*", "bloque*", "tendu*",
            "灵活", "柔韧", "僵", "紧绷", "拉伸", "活动度"]),
    ]
}
