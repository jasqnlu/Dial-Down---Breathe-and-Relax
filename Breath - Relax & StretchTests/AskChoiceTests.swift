import Foundation
import Testing
@testable import BreathRelaxStretch

/// "Did you mean…?": dictation heard "calf" as "cat" on device, and the model then
/// guessed neck, head, jaw and eyes. A word that sounds like a body area or names an
/// exercise is offered back as choices instead.
@MainActor
struct AskChoiceTests {
    private static func make(_ name: String, _ parts: [String]) -> Exercise {
        Exercise(name: name, type: .stretch, targetBodyParts: parts,
                 durationSeconds: 60, difficulty: 1, instructions: [])
    }

    /// Stored, so every use sees the same exercise IDs.
    private let catalog: [Exercise] = {
        let make = AskChoiceTests.make
        return [make("Cat-Cow Flow", ["Lower Back"]),
         make("Upper-Back Cat-Cow (Seated)", ["Upper Back"]),
         make("Left Calf Wall Stretch", ["Left Calves"]),
         make("Right Calf Wall Stretch", ["Right Calves"]),
         make("Seated Neck Tilt", ["Neck"]),
         make("Seated Twist", ["Lower Back"]),
         make("Seated Forward Fold", ["Hamstrings"]),
         make("Seated Chest Opener", ["Chest"])]
    }()

    /// The model's guess on device for "Can you add a cat exercise to this".
    private var hallucinated: AskIntent {
        AskIntent(areas: [.neck, .head, .jaw, .eyes], goal: nil, minutes: nil,
                  seriousness: .ok, isOffTopic: false)
    }

    private func pipeline(_ extracted: AskIntent? = nil) -> AskPipeline {
        AskPipeline(primary: extracted.map { StubExtractor(mode: .fixed($0)) })
    }

    // MARK: - When to ask

    @Test func catOffersCalvesAndTheCatCowExercises() async {
        let reply = await pipeline(hallucinated).respond(to: "Can you add a cat exercise to this", catalog: catalog)
        guard case .choose(let word, let intent, let choices) = reply else { Issue.record("got \(reply)"); return }
        #expect(word == "cat")
        #expect(choices == [.area(.calves), .exercise("Cat-Cow Flow"), .exercise("Upper-Back Cat-Cow (Seated)")])
        #expect(intent.count == 1, "\"a … exercise\" is kept for whichever choice is tapped")
    }

    /// Seen in the simulator: Cat-Cow Flow was offered while already in the routine.
    @Test func exercisesAlreadyInTheRoutineAreNotOffered() async {
        let inRoutine = Set(catalog.filter { $0.name == "Cat-Cow Flow" }.map(\.uuid))
        let reply = await pipeline().respond(to: "Can you add a cat exercise to this", catalog: catalog,
                                             excluding: inRoutine)
        guard case .choose(_, _, let choices) = reply else { Issue.record("got \(reply)"); return }
        #expect(choices == [.area(.calves), .exercise("Upper-Back Cat-Cow (Seated)")])
    }

    @Test(arguments: ["add a calf exercise", "help me sleep", "3 exercises for my lower back", "remove the last one"])
    func clearRequestsDontAsk(_ text: String) async {
        let reply = await pipeline().respond(to: text, catalog: catalog)
        if case .choose = reply { Issue.record("\(text): got \(reply)") }
    }

    @Test func aWordInManyExerciseNamesIsTooGenericToOffer() async {
        // "seated" is in four names; offering them all would be noise.
        let reply = await pipeline().respond(to: "something seated", catalog: catalog)
        if case .choose = reply { Issue.record("got \(reply)") }
    }

    @Test func safetyStillComesFirst() async {
        let reply = await pipeline().respond(to: "cat exercise, I have chest pain", catalog: catalog)
        guard case .safety(.urgent, _) = reply else { Issue.record("got \(reply)"); return }
    }

    // MARK: - Tapping a choice

    private func chatWithChoice() async -> (AskChatModel, AskMessage)? {
        let m = AskChatModel(pipeline: pipeline(hallucinated))
        await m.send("Can you add a cat exercise to this", catalog: catalog)
        guard let last = m.messages.last, case .choose? = last.reply else {
            Issue.record("got \(String(describing: m.messages.last?.reply))"); return nil
        }
        return (m, last)
    }

    @Test func choosingAnAreaBuildsThatRequest() async {
        guard let (m, message) = await chatWithChoice() else { return }
        m.choose(.area(.calves), for: message.id, catalog: catalog)
        #expect(m.draft.exercises.map(\.name) == ["Left Calf Wall Stretch", "Right Calf Wall Stretch"],
                "one exercise (a Left/Right pair counts once)")
        guard case .routine? = m.messages.last?.reply else { Issue.record("got \(String(describing: m.messages.last?.reply))"); return }
        #expect(m.chosen[message.id] == .area(.calves))
    }

    @Test func choosingAnExerciseAddsExactlyThatOne() async {
        guard let (m, message) = await chatWithChoice() else { return }
        m.choose(.exercise("Cat-Cow Flow"), for: message.id, catalog: catalog)
        #expect(m.draft.exercises.map(\.name) == ["Cat-Cow Flow"])
        #expect(m.messages.last?.reply == .draftChanged(.added(["Cat-Cow Flow"])))
    }

    @Test func choosingAPairedExerciseAddsBothSides() async {
        let m = AskChatModel(pipeline: pipeline())
        m.choose(.exercise("Calf Wall Stretch"), for: UUID(), catalog: catalog)
        #expect(m.draft.exercises.map(\.name) == ["Left Calf Wall Stretch", "Right Calf Wall Stretch"])
        #expect(m.messages.last?.reply == .draftChanged(.added(["Calf Wall Stretch"])))
    }

    @Test func aChoiceWorksOnce() async {
        guard let (m, message) = await chatWithChoice() else { return }
        m.choose(.exercise("Cat-Cow Flow"), for: message.id, catalog: catalog)
        let count = m.messages.count
        m.choose(.area(.calves), for: message.id, catalog: catalog)
        #expect(m.messages.count == count)
        #expect(m.draft.exercises.map(\.name) == ["Cat-Cow Flow"])
    }

    @Test func anExerciseAlreadyInTheRoutineIsNotAddedTwice() async {
        guard let (m, message) = await chatWithChoice() else { return }
        m.choose(.exercise("Cat-Cow Flow"), for: message.id, catalog: catalog)
        m.choose(.exercise("Cat-Cow Flow"), for: UUID(), catalog: catalog)
        #expect(m.draft.exercises.map(\.name) == ["Cat-Cow Flow"])
        #expect(m.messages.last?.reply == .draftChanged(.nothingToChange))
    }
}
