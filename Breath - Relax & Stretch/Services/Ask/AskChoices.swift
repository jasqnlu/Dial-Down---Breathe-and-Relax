import Foundation

/// Finds the word behind a "Did you mean…?" reply: one that matched no body area but is a
/// known dictation slip for one ("cat" for "calf") or appears in a few exercise names
/// ("cat" in "Cat-Cow Flow"). Only runs when the keyword parser found nothing literal.
enum AskChoices {
    /// The first such word with what it might mean: areas first, then exercises.
    /// Exercises in `excluding` (the routine being built) are never offered.
    static func find(in text: String, catalog: [Exercise],
                     excluding: Set<UUID> = []) -> (word: String, choices: [AskChoice])? {
        let words = PhraseMatcher.boundaryForm(PhraseMatcher.normalize(text))
            .split(separator: " ").map(String.init)
        let names = exerciseNames(in: catalog)
        let taken = Set(catalog.filter { excluding.contains($0.uuid) }.map { RoutinePicker.pairKey($0.name) })
        for word in words where word.count >= 3 && !stopWords.contains(word) {
            let areas = soundAlikes[word].map { [AskChoice.area($0)] } ?? []
            let matching = names.filter { $0.words.contains(word) }
            // A word in many names ("seated") says nothing about which one was meant.
            // Counted over the whole catalog, so the routine doesn't change what's generic.
            let exercises = (1...maxExercises).contains(matching.count)
                ? matching.filter { !taken.contains($0.name) }.map { AskChoice.exercise($0.name) } : []
            if !(areas + exercises).isEmpty { return (word, areas + exercises) }
        }
        return nil
    }

    private static let maxExercises = 3

    /// Each exercise's shared name (Left/Right pairs once), in catalog order, with its words.
    private static func exerciseNames(in catalog: [Exercise]) -> [(name: String, words: Set<String>)] {
        var seen = Set<String>()
        return catalog.compactMap { exercise in
            let name = RoutinePicker.pairKey(exercise.name)
            guard seen.insert(name).inserted else { return nil }
            let words = PhraseMatcher.boundaryForm(PhraseMatcher.normalize(name)).split(separator: " ")
            return (name, Set(words.map(String.init)))
        }
    }

    /// Dictation slips for body areas (English; dictation follows the device language).
    private static let soundAlikes: [String: AskArea] = [
        "cat": .calves, "cats": .calves, "caf": .calves, "caff": .calves, "calve": .calves,
        "carve": .calves, "carves": .calves,
        "nick": .neck, "knick": .neck,
        "hep": .hips,
        "soldier": .shoulders, "soldiers": .shoulders,
        "glues": .glutes,
        "feat": .feet,
        "quod": .quads, "quods": .quads,
    ]

    /// Request filler that can't name an exercise.
    private static let stopWords: Set<String> = [
        "add", "adding", "can", "could", "would", "should", "you", "the", "this", "that", "these",
        "those", "exercise", "exercises", "stretch", "stretches", "stretching", "routine",
        "routines", "workout", "one", "ones", "another", "more", "please", "for", "like", "get",
        "some", "give", "want", "with", "and", "need", "just", "also", "any", "something",
        "anything", "make", "let", "does", "have", "has", "are", "was", "what", "how", "about",
        "from", "into", "onto", "your", "our", "out", "now", "today", "time", "minute",
        "minutes", "move", "moves", "pose", "poses", "good", "nice", "new", "next", "not",
        "yes", "yeah", "okay", "hey", "there", "here", "where", "help", "really", "very",
        "much", "lot", "lots", "bit", "little", "few", "couple", "all", "two", "three", "four",
        "five", "previous", "last", "first", "other", "different", "same", "them", "they",
        "too", "but", "maybe", "try", "show", "find", "use", "put", "keep", "back",
        "para", "por", "con", "una", "uno", "que", "los", "las", "del", "otro", "otra",
        "pour", "avec", "une", "des", "les", "est", "autre",
    ]
}
