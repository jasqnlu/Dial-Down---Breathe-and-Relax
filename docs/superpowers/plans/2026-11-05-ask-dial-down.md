# Ask Dial Down Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A floating "Ask" button that turns a spoken or typed request ("ease my lower back pain") into a safety-screened, ready-to-start routine from the existing catalog — fully on-device and offline.

**Architecture:** Five-stage pipeline: input (keyboard / on-device speech) → `SafetyScreener` (deterministic, 4 languages) → `IntentExtractor` (Foundation Models when available, keyword dictionary otherwise; both emit `AskIntent`) → `RoutinePicker` (wraps existing `RegionExerciseResolver` + `GoalMeta`) → chat sheet with Start → `SessionPlayerView`. Only the extractor touches AI; everything else is plain, unit-tested Swift.

**Tech Stack:** Swift, SwiftUI, SwiftData, FoundationModels (iOS 26), Speech (iOS 26 on-device), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-04-ask-dial-down-design.md`

## Global Constraints

- iOS 26.0 deployment target; no third-party dependencies; no network calls anywhere in this feature.
- Languages: English, Spanish, French, Simplified Chinese (`AppLanguage.en/.es/.fr/.zhHans`). Screener + keyword lists exist for all four; screener checks all four regardless of app language.
- The AI never names exercises; it only fills `AskIntent`. Breath-type exercises never appear in an area request. Left/Right pairs are always both present and adjacent.
- AI may raise safety level, never lower it. `.urgent` has no "anyway" path. Emergency button opens `tel:` URL, never auto-dials.
- "Anyway" mode: difficulty == 1 only, never relaxed; banner "Stop immediately if anything feels off."; every routine shows "Stop if anything hurts sharply."
- Default routine target 300 s (≈5 min), 4–6 slots; `minutes` honoured, clamped to 1…20.
- Do not change `AppTab` raw values. Do not put a `@FocusState` TextField in a `.toolbar`.
- All user-facing strings localized via the String Catalog as `LocalizedStringKey`/`String(localized:)` — never pass a plain `String` variable to `Text` for UI copy.
- Tests: Swift Testing, `@testable import BreathRelaxStretch`, files in `Breath - Relax & StretchTests/` (auto-synced). Test command:
  `xcodebuild test -project "Breath - Relax & Stretch.xcodeproj" -scheme BreathRelaxStretch -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:"Breath - Relax & StretchTests/<Suite>"`
- Branch: `feature/ask-dial-down`, created from `seperate-main` **with its uncommitted work carried over** (`git switch -c`). Commit only this feature's files: `git add <paths>` then plain `git commit` (never `git commit -- <paths>`).
- After code changes: `graphify update .` from repo root.

## Review Focus

1. Empty, whitespace-only, or emoji-only input → `.clarify` reply, no crash, no routine. (Task 6 test)
2. Uppercase / accented / unaccented variants ("DOLOR EN EL PECHO", "douleur thoracique", "douleur thoracique" without accents, "胸口疼") → screener still fires. (Task 2 tests)
3. Out-of-range durations ("60 minutes", "0 min") → clamped to 20 / default; never an empty or 40-exercise routine. (Task 4 tests)
4. Catalog not yet seeded (empty `[Exercise]`) → `.noMatch`, no crash. (Task 4 + Task 6 tests)
5. Mic or speech permission denied, or on-device speech asset unavailable for the locale → mic shows explanation + Settings link; typing still works. (Task 7 test on state mapping)

---

### Task 1: Branch + `AskIntent` vocabulary

**Files:**
- Create: `Breath - Relax & Stretch/Services/Ask/AskIntent.swift`
- Test: `Breath - Relax & StretchTests/AskIntentTests.swift`

**Interfaces:**
- Produces:
  - `enum AskArea: String, CaseIterable, Codable` — side-neutral areas: `neck, head, jaw, eyes, upperBack, shoulders, chest, core, obliques, lats, lowerBack, biceps, triceps, forearms, hands, glutes, hipFlexors, hips, adductors, quads, hamstrings, calves, shins, feet`.
  - `var AskArea.regions: [String]` — catalog tag names fed to `RegionExerciseResolver`. Pinned values: `lowerBack → ["Lower Back","Spinal Erectors","Lower Spine"]`, `neck → ["Front Neck","Back Neck","Neck"]`, `upperBack → ["Left Trapezius","Right Trapezius"]`, `shoulders → ["Left Shoulder","Right Shoulder","Left Shoulder Joint","Right Shoulder Joint"]`, `hips → ["Left Hip","Right Hip"]`, `head → ["Head","Forehead","Left Temple","Right Temple"]`, `jaw → ["Left Jaw","Right Jaw"]`, `eyes → ["Left Eye","Right Eye"]`; all other paired areas → both `MuscleGroup` sides (e.g. `hamstrings → ["Left Hamstrings","Right Hamstrings"]`).
  - `enum AskGoal: String, CaseIterable, Codable` — raw values equal `GoalMeta` ids: `flexibility, stress_relief, pain_relief, better_breathing, wake_up, unwind`.
  - `enum SafetyLevel: Int, Comparable, Codable { case ok = 0, concerning, urgent }`
  - `struct AskIntent: Equatable { var areas: [AskArea]; var goal: AskGoal?; var minutes: Int?; var seriousness: SafetyLevel; var isOffTopic: Bool; var isEmpty: Bool { areas.isEmpty && goal == nil } }`
  - `protocol IntentExtractor { func extract(_ text: String) async throws -> AskIntent }`

- [ ] **Step 1:** `git switch -c feature/ask-dial-down` (from `seperate-main`; uncommitted work comes along). Expected: `git branch --show-current` → `feature/ask-dial-down`.
- [ ] **Step 2: Write failing tests** `AskIntentTests`:
  - `everyRegionIsARealCatalogTag`: load `SeedData.json` from the app bundle, collect all `targetBodyParts`; `#expect` every `AskArea.allCases.flatMap(\.regions)` element is in that set.
  - `goalRawValuesMatchGoalMeta`: `#expect(Set(AskGoal.allCases.map(\.rawValue)) == Set(GoalMeta.all.map(\.id)))`.
  - `lowerBackRegions`: `#expect(AskArea.lowerBack.regions == ["Lower Back","Spinal Erectors","Lower Spine"])`.
  - `safetyOrdering`: `#expect(SafetyLevel.urgent > .concerning && SafetyLevel.concerning > .ok)`.
- [ ] **Step 3:** Run suite `AskIntentTests` → FAIL (types missing).
- [ ] **Step 4:** Implement the types above in `AskIntent.swift`.
- [ ] **Step 5:** Run suite → PASS.
- [ ] **Step 6:** Commit `feat(ask): intent vocabulary`.

### Task 2: `SafetyScreener` (4 languages)

**Files:**
- Create: `Breath - Relax & Stretch/Services/Ask/SafetyScreener.swift`
- Test: `Breath - Relax & StretchTests/SafetyScreenerTests.swift`

**Interfaces:**
- Consumes: `SafetyLevel` (Task 1).
- Produces: `enum SafetyScreener { static func screen(_ text: String) -> SafetyLevel }` and `static func normalize(_ text: String) -> String` (lowercased, diacritics folded via `folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)`, collapsed whitespace, straight apostrophes).

Matching: substring match of normalized phrase in normalized text (works for Chinese). Check urgent lists of all four languages first, then concerning. Seed lists (builder may extend, must keep these):
- urgent — en: "chest pain", "can't breathe", "cant breathe", "trouble breathing", "unbearable", "worst pain", "passed out", "fainted", "can't move my legs", "lost control of my bladder"; es: "dolor en el pecho", "no puedo respirar", "insoportable", "me desmaye"; fr: "douleur thoracique", "douleur a la poitrine", "je ne peux pas respirer", "insupportable", "evanoui"; zh: "胸痛", "胸口疼", "喘不过气", "无法呼吸", "晕倒", "疼得受不了".
- concerning — en: "sharp", "shooting", "numb", "tingling", "pins and needles", "after a fall", "fell", "accident", "swollen", "for weeks", "getting worse"; es: "punzante", "entumecid", "hormigueo", "despues de una caida", "hinchad", "empeora"; fr: "aigu", "lancinant", "engourdi", "fourmillement", "apres une chute", "enfle", "empire"; zh: "刺痛", "麻木", "发麻", "摔倒", "肿", "越来越疼".

- [ ] **Step 1: Write failing tests** (parameterized `@Test(arguments:)`):
  - urgent: `"I have chest pain"`, `"DOLOR EN EL PECHO"`, `"douleur thoracique"`, `"j'ai une douleur à la poitrine"`, `"胸口疼"` → `.urgent`.
  - concerning: `"sharp pain shooting down my leg"`, `"my foot feels numb"`, `"hormigueo en la pierna"`, `"engourdi"`, `"腿发麻"`, `"my back hurts after a fall"` → `.concerning`.
  - ok: `"give me exercises that can ease my lower back pain"`, `"tight hamstrings"`, `"dolor de espalda baja"`, `""`, `"🙂"` → `.ok`.
  - `crossLanguage`: Spanish phrase inside otherwise English text → `.urgent`.
  - `urgentBeatsConcerning`: `"sharp chest pain"` → `.urgent`.
- [ ] **Step 2:** Run `SafetyScreenerTests` → FAIL.
- [ ] **Step 3:** Implement. Phrase lists are normalized once (static lazy) so accented and unaccented forms both match.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(ask): deterministic safety screener (en/es/fr/zh)`.

### Task 3: `KeywordIntentExtractor` (4 languages)

**Files:**
- Create: `Breath - Relax & Stretch/Services/Ask/KeywordIntentExtractor.swift`
- Test: `Breath - Relax & StretchTests/KeywordIntentExtractorTests.swift`

**Interfaces:**
- Consumes: `AskIntent`, `AskArea`, `AskGoal`, `IntentExtractor`, `SafetyScreener.normalize`.
- Produces: `struct KeywordIntentExtractor: IntentExtractor` with `func extract(_:) async throws -> AskIntent` and a sync `func intent(for text: String) -> AskIntent` (used directly by tests and as the AI fallback). `seriousness` is always `.ok`; `isOffTopic` is `false` (keyword path can't judge; empty intent → clarify).

Rules: area synonyms checked longest-phrase-first so "lower back" wins over "back"; bare "back" → `.lowerBack`; sides ("left", "right", "izquierd", "derech", "gauche", "droit", "左", "右") are ignored. Minutes: first integer followed by `min|minute|minuto|分钟` → `minutes`; words "quick"/"rápido"/"rapide"/"快速" → 3. Goal words per spec (pain/sore/ache/hurt → `pain_relief`, stress/anxious → `stress_relief`, sleep/wind down → `unwind`, wake up/morning → `wake_up`, breathe/breathing → `better_breathing`, flexible/tight/stiff → `flexibility`) in all four languages; when both pain and tight words appear, `pain_relief` wins.

- [ ] **Step 1: Write failing tests:**
  - `"give me exercises that can ease my lower back pain"` → `areas == [.lowerBack]`, `goal == .pain_relief`, `minutes == nil`.
  - `"my left hip is tight"` → `[.hips]`, `.flexibility`.
  - `"5 minute neck stretch"` → `[.neck]`, `minutes == 5`.
  - `"dolor de espalda baja"` → `[.lowerBack]`, `.pain_relief`; `"j'ai mal au bas du dos"` → `[.lowerBack]`, `.pain_relief`; `"腰疼"` → `[.lowerBack]`, `.pain_relief`.
  - `"help me sleep"` → `areas == []`, `.unwind`.
  - `"tight hamstrings and calves"` → `Set(areas) == [.hamstrings, .calves]`.
  - `"what's the weather"` → `isEmpty == true`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement with per-language `[String: AskArea]` / `[String: AskGoal]` tables over normalized text.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(ask): keyword intent extractor (en/es/fr/zh)`.

### Task 4: `RoutinePicker`

**Files:**
- Create: `Breath - Relax & Stretch/Services/Ask/RoutinePicker.swift`
- Test: `Breath - Relax & StretchTests/RoutinePickerTests.swift`

**Interfaces:**
- Consumes: `AskIntent` (Task 1), `RegionExerciseResolver(regions:exercises:)`, `GoalMeta.all`.
- Produces:
  - `struct AskRoutine: Equatable { let exercises: [Exercise]; let isGentle: Bool; var totalSeconds: Int }` (Equatable by exercise uuids + isGentle).
  - `enum RoutinePicker { static func pick(intent: AskIntent, from catalog: [Exercise], gentle: Bool = false) -> AskRoutine? }` — `nil` when nothing matches.
  - `static func pairKey(_ name: String) -> String` — strips a leading `"Left "`/`"Right "`.

Algorithm:
1. Candidates: if `intent.areas` non-empty → resolver over `intent.areas.flatMap(\.regions)`; ordered = goal-list members of (`direct + related`) first (in goal-list order), then remaining `direct`, then remaining `related`. Exclude `.breath`. If areas empty and goal set → `GoalMeta` list for that goal resolved by name against catalog (breath allowed). Neither → `nil`.
2. `gentle` → keep `difficulty == 1` only.
3. Group into slots by `pairKey`; a slot holds both sides (Left first) or a single bilateral exercise.
4. Target seconds = `clamp(m, 1...20) * 60` where `m = intent.minutes` if it is `> 0`, else `5`. Add slots in order until total ≥ target; then if slots < 4 keep adding until 4 or exhausted, but never exceed 6 slots unless `minutes` was given (then cap is total ≤ target + one slot).
5. Empty → `nil`.

- [ ] **Step 1: Write failing tests** (build exercises with the `makeExercise` pattern from `ExerciseGraphGroupingTests`, adding `difficulty`/`type` params):
  - `lowerBackPainUsesGoalOrderFirst`: catalog has "Pelvic Tilt"(Lower Back), "Cat-Cow Flow"(Spinal Erectors), "Lumbar Roll"(Lower Back, not in goal) → result starts with goal-list members in `pain_relief` order ("Cat-Cow Flow", "Pelvic Tilt"), then "Lumbar Roll".
  - `pairsStayTogether`: "Left Seated Spinal Twist" + "Right Seated Spinal Twist" (Lower Back) → both present, adjacent, Left first.
  - `neverIncludesBreathForAreaRequest`: a `.breath` exercise tagged "Lower Back" → absent.
  - `goalOnlyAllowsBreath`: intent `goal: .better_breathing`, no areas, catalog with "Box Breathing" (breath) → included.
  - `gentleKeepsOnlyDifficultyOne`: difficulty-2 lower-back exercise absent when `gentle: true`; if only difficulty-2 exist → `nil`.
  - `defaultTargetsAboutFiveMinutes`: ten 60-s lower-back exercises → 5 slots, total 300.
  - `minutesClamped`: `minutes: 60` with forty 60-s exercises → total ≤ 20*60 + 60; `minutes: 0` → same result as `minutes: nil` (5-min default).
  - `emptyCatalogReturnsNil`: `[]` → `nil`.
  - `sidedRequestStillBothSides`: intent `[.hips]` with "Left Hip Opener"(Left Hip) + "Right Hip Opener"(Right Hip) → both.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(ask): routine picker over existing resolver + goals`.

### Task 5: `ModelIntentExtractor` (Foundation Models)

**Files:**
- Create: `Breath - Relax & Stretch/Services/Ask/ModelIntentExtractor.swift`
- Test: `Breath - Relax & StretchTests/ModelIntentExtractorTests.swift`

**Interfaces:**
- Consumes: `IntentExtractor`, `AskIntent`, `AskArea`, `AskGoal`, `SafetyLevel`.
- Produces:
  - `struct ModelIntentExtractor: IntentExtractor` — `static var isAvailable: Bool` (`SystemLanguageModel.default.availability == .available`).
  - `@Generable struct GeneratedIntent` with `areas: [AskArea]` (≤4), `goal: AskGoal?`, `minutes: Int?`, `seriousness: SafetyLevel`, `isOffTopic: Bool`; `AskArea`, `AskGoal`, `SafetyLevel` gain `@Generable` conformance (in this file via extensions if the macro permits, else on the declarations).
  - `func GeneratedIntent.toIntent() -> AskIntent`.

Instructions text (the session's `instructions`): explain the app is a stretching/breathing app; map the user's words to the listed areas and goals; treat Left/Right as the same area; set `seriousness` to urgent for chest pain, breathing trouble, fainting, unbearable pain, loss of bladder/bowel control or leg control; concerning for sharp/shooting pain, numbness, tingling, injury from a fall/accident, swelling, pain lasting weeks; `isOffTopic` for anything not about stretching, breathing, tension or soreness. Never name exercises. One `LanguageModelSession` per request (no history).

- [ ] **Step 1: Write failing tests** (no model needed):
  - `conversionPreservesFields`: `GeneratedIntent(areas: [.lowerBack], goal: .pain_relief, minutes: 7, seriousness: .concerning, isOffTopic: false).toIntent()` equals matching `AskIntent`.
  - `conversionClampsAndDedupes`: duplicate areas collapse preserving order; `minutes: 500` → `20`; `minutes: 0` → `nil`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement extractor: `session.respond(to: text, generating: GeneratedIntent.self)`.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(ask): Foundation Models intent extractor`.

### Task 6: `AskPipeline` orchestration

**Files:**
- Create: `Breath - Relax & Stretch/Services/Ask/AskPipeline.swift`
- Test: `Breath - Relax & StretchTests/AskPipelineTests.swift`

**Interfaces:**
- Consumes: Tasks 1–5.
- Produces:
  - `enum AskReply: Equatable { case routine(AskRoutine, intent: AskIntent); case safety(SafetyLevel, intent: AskIntent); case clarify; case offTopic; case noMatch(intent: AskIntent) }`
  - `struct AskPipeline { init(primary: IntentExtractor?, fallback: KeywordIntentExtractor = .init(), timeout: Duration = .seconds(6)); func respond(to text: String, catalog: [Exercise]) async -> AskReply; func gentleRoutine(for intent: AskIntent, catalog: [Exercise]) -> AskReply }`
  - `static func live() -> AskPipeline` — `primary` = `ModelIntentExtractor()` if `isAvailable`, else `nil`.

Flow: trim; empty/no letters → `.clarify`. `screen = SafetyScreener.screen(text)`. Intent = primary (with timeout; any throw/timeout → fallback) or fallback. `level = max(screen, intent.seriousness)`. `level > .ok` → `.safety(level, intent:)`. `intent.isOffTopic` → `.offTopic`. `intent.isEmpty` → `.clarify`. `RoutinePicker.pick` → `.routine` or `.noMatch`. `gentleRoutine` calls picker with `gentle: true`; nil → `.noMatch`.

- [ ] **Step 1: Write failing tests** with a `StubExtractor: IntentExtractor` (returns fixed intent / throws / sleeps):
  - `emptyInputClarifies`: `""`, `"   "`, `"🙂🙂"` → `.clarify`.
  - `screenerOverridesCalmModel`: stub returns `.ok`, text "chest pain" → `.safety(.urgent, …)`.
  - `modelCanRaiseLevel`: stub `.concerning`, text "my back" → `.safety(.concerning, …)`.
  - `throwingModelFallsBackToKeywords`: stub throws, text "lower back pain" → `.routine` with lower-back exercises.
  - `slowModelFallsBackToKeywords`: stub sleeps 2 s, timeout 0.1 s → `.routine`.
  - `offTopic`: stub `isOffTopic: true` → `.offTopic`.
  - `emptyCatalogNoMatch`: "lower back pain", catalog `[]` → `.noMatch`.
  - `gentleRoutineOnlyDifficultyOne`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement (timeout via `withThrowingTaskGroup` racing a `Task.sleep`).
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(ask): pipeline with safety-first ordering and AI fallback`.

### Task 7: On-device speech input

**Files:**
- Create: `Breath - Relax & Stretch/Services/Ask/SpeechInput.swift`
- Modify: `Breath - Relax & Stretch.xcodeproj/project.pbxproj` (both app build configs, next to existing `INFOPLIST_KEY_NS…UsageDescription` lines ~410 and ~463)
- Test: `Breath - Relax & StretchTests/SpeechInputTests.swift`

**Interfaces:**
- Produces:
  - `@MainActor @Observable final class SpeechInput { var state: SpeechState; var transcript: String; func start(locale: Locale) async; func stop() -> String; func cancel() }`
  - `enum SpeechState: Equatable { case idle, listening, unavailable(SpeechUnavailableReason) }`; `enum SpeechUnavailableReason: Equatable { case micDenied, speechDenied, localeUnsupported }`
  - `static func reason(micGranted: Bool, speechAuthorized: Bool, localeSupported: Bool) -> SpeechUnavailableReason?` (pure; tested).

Use iOS 26 `SpeechAnalyzer` + `SpeechTranscriber` with on-device assets (install via `AssetInventory` if needed; offline after install), or `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` — builder's choice, on-device only. Locale = `AppLanguage` locale if set, else device locale. Volatile results update `transcript` live.

Info.plist keys (both configs):
- `INFOPLIST_KEY_NSMicrophoneUsageDescription = "Lets you ask for exercises by voice. Audio is processed on your iPhone and never leaves it.";`
- `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription = "Turns what you say into text on your iPhone so Dial Down can find matching exercises.";`

- [ ] **Step 1: Write failing tests** for `reason(...)`: mic denied → `.micDenied` (takes precedence); speech denied → `.speechDenied`; unsupported → `.localeUnsupported`; all good → `nil`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement `SpeechInput` + add the two plist keys.
- [ ] **Step 4:** Run → PASS; `grep -c NSMicrophoneUsageDescription` on pbxproj → `2`.
- [ ] **Step 5:** Commit `feat(ask): on-device speech input`.

### Task 8: Chat sheet

**Files:**
- Create: `Breath - Relax & Stretch/Views/Ask/AskChatModel.swift`, `Breath - Relax & Stretch/Views/Ask/AskChatSheet.swift`, `Breath - Relax & Stretch/Views/Ask/AskRoutineCard.swift`, `Breath - Relax & Stretch/Views/Ask/AskSafetyCard.swift`
- Modify: `Breath - Relax & Stretch/Resources/Localizable.xcstrings` — add strings with es/fr/zh-Hans translations.
- Test: `Breath - Relax & StretchTests/AskChatModelTests.swift`

**Interfaces:**
- Consumes: `AskPipeline`, `AskReply`, `AskRoutine`, `SpeechInput`.
- Produces:
  - `@MainActor @Observable final class AskChatModel { init(pipeline: AskPipeline); var messages: [AskMessage]; var isThinking: Bool; func send(_ text: String, catalog: [Exercise]) async; func showGentleAnyway(for messageID: UUID, catalog: [Exercise]) }`
  - `struct AskMessage: Identifiable, Equatable { let id: UUID; enum Role { case user, reply }; let role: Role; let text: String; let reply: AskReply? }`
  - `struct AskChatSheet: View { init(model: AskChatModel, initialText: String?) }` — reads catalog via `@Query`; presents `SessionPlayerView(exercises:)` via `.fullScreenCover` on Start.

UI copy (localize all): reply for routine "Here's a gentle %d-minute routine for your %@."; clarify "Tell me where you feel it or what you'd like — for example, \"stiff neck\" or \"help me sleep\"."; offTopic "I can help you find stretches and breathing exercises."; noMatch "I couldn't find stretches for that yet."; concerning "This sounds like more than everyday tightness. It's worth checking with a doctor before stretching."; urgent "If the pain is severe or came on suddenly, please call emergency services."; buttons "Call emergency services" (`tel://` — use `911`/`112` by region: `Locale.current.region == .unitedStates || .canada ? "911" : "112"`), "I understand — show gentle stretches anyway" (concerning only), "Start"; notes "Stop if anything hurts sharply." / gentle banner "Stop immediately if anything feels off."; chips "Stiff neck", "Lower back", "Can't sleep", "Tight hips". Routine rows show a pair as one row "<name without side> · L + R" with combined duration.

- [ ] **Step 1: Write failing tests** (stub pipeline via `AskPipeline(primary: StubExtractor…)`):
  - `sendAppendsUserThenReply`: after `send("lower back pain")` → 2 messages, roles user/reply, reply is `.routine`.
  - `gentleAnywayReplacesSafetyWithRoutine`: send "sharp pain in my lower back" → `.safety(.concerning)`; `showGentleAnyway` → new reply `.routine` with `isGentle == true`.
  - `gentleAnywayIgnoredForUrgent`: on `.urgent` message → no new message.
  - `emptySendDoesNothing`: `send("  ")` → `.clarify` reply appended (user bubble omitted for empty text).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement model + views in the black + pastel theme (lavender user bubble, `card` reply bubble, mint Start, coral emergency, warm-amber concerning card) per mockup `ask-entry.html`.
- [ ] **Step 4:** Run → PASS; build succeeds.
- [ ] **Step 5:** Commit `feat(ask): chat sheet with routine and safety cards`.

### Task 9: Floating Ask button + HomeView wiring

**Files:**
- Create: `Breath - Relax & Stretch/Views/Ask/AskButton.swift`
- Modify: `Breath - Relax & Stretch/Views/Home/HomeView.swift` (overlay above `CustomTabBar`), `Breath - Relax & Stretch/Views/Home/CustomTabBar.swift:109` (`floatingTabBarClearance` adds `AskButton.clearance`)
- Create: `Breath - Relax & StretchUITests/AskFlowUITests.swift`

**Interfaces:**
- Consumes: `AskChatModel`, `AskChatSheet`, `SpeechInput`, `TourCoordinator.isActive`.
- Produces: `struct AskButton: View` with `static let clearance: CGFloat` (button height + spacing); accessibility identifiers `ask.button`, `ask.bar`, `ask.field`, `ask.mic`, `ask.sheet`, `ask.start`.

Behaviour (mockup `ask-entry-v2.html`): resting 50-pt lavender→blue circle bottom-right above the bar. **Tap** → `matchedGeometryEffect` morph into ask bar (focused `TextField` in content, not toolbar; mic button; dimmed backdrop; tap backdrop dismisses). Submit or mic-stop → present `AskChatSheet(initialText:)` as `.sheet` with `.presentationDetents([.large])`. **Long press (0.3 s)** → light haptic, `SpeechInput.start`, live transcript bubble; release → send; drag > 60 pt away → cancel. Hidden when `tourCoordinator.isActive`. Sessions/full-screen covers already sit above HomeView, so no extra hiding needed. VoiceOver: label "Ask Dial Down", hint "Double-tap to type. Hold to speak."; long-press exposed as an accessibility action "Speak".

- [ ] **Step 1: Write failing UI test** `testTypeLowerBackShowsRoutine`: launch, tap `ask.button`, type "lower back pain" into `ask.field`, return → `ask.sheet` exists and `ask.start` exists; `testUrgentShowsNoStart`: type "chest pain" → emergency button exists, `ask.start` does not.
- [ ] **Step 2:** Run `-only-testing:"Breath - Relax & StretchUITests/AskFlowUITests"` → FAIL.
- [ ] **Step 3:** Implement button, morph, hold-to-talk, HomeView overlay, clearance change.
- [ ] **Step 4:** Run UI tests → PASS; full unit suite → no new failures vs. baseline (note: ~50 UI tests already fail on `seperate-main`; compare against that list, not zero).
- [ ] **Step 5:** Verify visually via the repo's `verify` skill: screenshots of resting button on Today and Routines (no overlap with list rows' trailing controls), expanded bar, chat with routine, urgent card. Hidden during tour.
- [ ] **Step 6:** `graphify update .` from repo root; commit `feat(ask): floating Ask button with tap-to-type and hold-to-talk`.
