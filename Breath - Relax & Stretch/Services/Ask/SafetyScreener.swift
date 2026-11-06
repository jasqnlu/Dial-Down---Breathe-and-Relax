import Foundation

/// Deterministic red-flag phrase checker. Runs before any routine is built.
/// Checks all four app languages regardless of the current app language.
nonisolated enum SafetyScreener {
    static func screen(_ text: String) -> SafetyLevel {
        let haystack = PhraseMatcher.boundaryForm(PhraseMatcher.normalize(text))
        if urgentPhrases.contains(where: { $0.matches(haystack) }) { return .urgent }
        if concerningPhrases.contains(where: { $0.matches(haystack) }) { return .concerning }
        return .ok
    }

    /// Whether the text describes any symptom at all. The AI may raise the safety level
    /// only when it does; deliberately broad, so missing a word errs toward listening.
    static func describesSymptom(_ text: String) -> Bool {
        let haystack = PhraseMatcher.boundaryForm(PhraseMatcher.normalize(text))
        return (symptomWords + urgentPhrases + concerningPhrases).contains { $0.matches(haystack) }
    }

    private static let symptomWords: [PhraseMatcher] = [
        // en
        "pain*", "hurt*", "ache*", "aching", "achy", "sore*", "injur*", "strain*", "sprain*",
        "pulled", "tweaked", "tear", "torn", "dizz*", "faint*", "lightheaded", "light headed",
        "breath*", "chest", "heart", "throb*", "burn*", "cramp*", "spasm*", "stiff*", "weak*",
        "bleed*", "bruis*", "warm", "hot", "red", "fever*", "can t feel", "can t move", "cannot",
        "fall", "fell", "pressure", "tight*", "pinch*", "locked", "giving out", "gave out",
        "blood clot", "clot*", "nause*", "vomit*", "pregnan*", "surgery", "operation",
        // es
        "dolor*", "duele*", "dolio", "molest*", "lesion*", "lastim*", "mare*", "pecho",
        "respir*", "calambre*", "rigid*", "debil*", "sangr*", "moreton*", "caliente", "fiebre",
        "cai", "caida", "embaraz*", "cirugia", "operacion", "coagulo*",
        // fr
        "douleur*", "douloureu*", "mal", "blesse*", "blessure*", "vertige*", "poitrine",
        "respir*", "crampe*", "raide*", "faible*", "saign*", "bleu", "chaud", "fievre",
        "tombe*", "chute", "enceinte", "chirurgie", "caillot*",
        // zh
        "疼", "痛", "伤", "晕", "胸", "呼吸", "麻", "肿", "抽筋", "僵", "无力", "流血", "发烧",
        "发热", "摔", "怀孕", "手术", "血栓", "不舒服", "难受",
    ].map { PhraseMatcher($0) }

    // Phrases ending in "*" are deliberate stems (match as a word prefix); all other
    // Latin-script phrases match whole words only. CJK phrases match as substrings.
    // Avoid stems that catch everyday words: no "numb*" ("number"), no "fall*"
    // ("falling asleep"), no bare "麻" (in "麻烦").
    private static let urgentPhrases: [PhraseMatcher] = [
        // en
        "chest pain", "can't breathe", "cant breathe", "cannot breathe", "can not breathe",
        "trouble breathing", "difficulty breathing", "shortness of breath", "short of breath",
        "unbearable", "worst pain", "passed out", "passing out", "blacked out", "fainted",
        "can't move my leg", "can't move my legs", "cannot move my legs", "can't feel my legs",
        "lost control of my bladder", "lost control of my bowels", "bladder control", "bowel control",
        "incontinen*", "heart attack", "stroke",
        "pain in my chest", "chest tightness", "chest pressure",
        // es
        "dolor en el pecho", "dolor de pecho", "no puedo respirar", "dificultad para respirar",
        "insoportable", "me desmaye", "me desmayo", "no puedo mover las piernas",
        "control de esfinteres",
        // fr
        "douleur thoracique", "douleur a la poitrine", "mal a la poitrine",
        "je ne peux pas respirer", "difficulte a respirer", "insupportable", "evanoui*",
        "controle de la vessie",
        // zh
        "胸痛", "胸口疼", "胸闷", "喘不过气", "无法呼吸", "呼吸困难", "晕倒", "疼得受不了",
        "大小便失禁", "失禁", "腿动不了",
    ].map { PhraseMatcher($0) }

    private static let concerningPhrases: [PhraseMatcher] = [
        // en
        "sharp", "shooting", "shoots", "stabbing", "numb", "numbness", "numbing", "numbed",
        "tingl*", "pins and needles", "swell*", "swollen",
        "after a fall", "had a fall", "bad fall", "fell", "accident*",
        "for weeks", "for months", "getting worse", "gets worse", "worsening",
        "won't go away", "wont go away", "doesn't go away", "not going away",
        // es
        "punzante*", "entumecid*", "hormigue*", "adormecid*", "hinchad*", "hinchazon",
        "dolor agud*", "despues de una caida", "me cai", "accidente*", "empeor*",
        "desde hace semanas",
        // fr
        "aigu", "aigue", "lancinant*", "engourdi*", "fourmill*", "picote*", "enfle*", "gonfl*",
        "apres une chute", "je suis tombe*", "ca empire", "de pire en pire", "depuis des semaines",
        // zh
        "刺痛", "针扎", "麻木", "发麻", "摔倒", "跌倒", "车祸", "肿", "越来越疼", "越来越痛", "好几周",
    ].map { PhraseMatcher($0) }
}
