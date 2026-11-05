# Ask Dial Down — voice/text exercise finder

**Date:** 2026-11-04 · **Status:** design, awaiting approval
**Mockups:** `.superpowers/brainstorm/31529-1793860325/content/ask-entry-v2.html` (chosen flow), `ask-entry.html` (chat + safety screens)

## Intent

A user who is sore or stiff should be able to say or type what's bothering them —
*"give me exercises that can ease my lower back pain"* — and get back a short,
ready-to-start routine built from the app's own catalog. It must work anywhere:
at home, at the gym (noisy), on a plane (offline, may not want to talk aloud).

Today the only ways to get there are browsing the Exercises tab or tapping the
Body Map. Both require the user to translate "my lower back hurts" into the app's
categories themselves. This feature does that translation for them.

## Decisions made with Jason

- **Result = a ready-to-start mini routine**, like the Body Map's, not a list to browse.
- **No custom model, no server.** Use Apple's on-device pieces:
  - Speech → text: Apple's on-device speech recognition.
  - Text → intent: Apple's on-device Foundation Models framework (iOS 26; app already targets 26.0).
  - Fallback on phones without Apple Intelligence (or when it's off/unavailable):
    keyword ("buzzword") matching, e.g. "low" + "back" → Lower Back.
- **The AI never invents exercises.** It only extracts intent (body areas, goal,
  duration). Existing app code picks exercises from the catalog.
- **Safety check for pain requests.** If the request sounds serious, show advice
  instead of a routine: see a doctor; call emergency services if severe.
  - For *concerning* cases, offer "I understand — show gentle stretches anyway".
    That routine opens with a clear "stop immediately if anything feels off" message.
  - Every routine from this feature carries a "Stop if anything hurts sharply" note.
- **Entry point = "B that opens into C"** (see mockup v2):
  1. A small floating button sits above the tab bar on every tab. Tab bar unchanged.
  2a. **Tap** → button expands into an ask bar ("What's bothering you today?") with
      the keyboard up and a mic button inside it.
  2b. **Press and hold** → starts listening immediately; live transcript shown; release sends.
  3. **Send** → a chat sheet slides up showing the reply and the routine with a **Start** button.
- **Typing is a first-class path**, not a fallback (planes, public places, noisy gyms).
  The transcript of spoken input is always shown so users can see/fix what was heard.

## Goals

- Turn a free-form sentence into a startable routine in one step, offline, on-device.
- Same behaviour on every iOS 26 device (AI path where available, keyword path elsewhere) — both produce the same intent shape and feed the same picker.
- Safety screening that is deterministic and runs before any routine is built.

## Non-goals (v1)

- Training or hosting any model; any network call.
- General chit-chat or health Q&A. Off-topic messages get a short "I can help you find stretches and breathing exercises" reply.
- Diagnosing or naming conditions.
- Saving chat history across launches. (The chat lives for the app session only.)
- Saving the generated routine as a named Routine (possible follow-up).
- Changing the tab bar / `AppTab` enum.

## Anti-goals (would be a failure even if it "works")

- Suggesting an exercise that isn't in the catalog, or a breathing-only exercise for a body-area request.
- A routine with only the Left side of a Left/Right pair.
- Handing a routine to someone describing red-flag symptoms without the safety message first.
- Different results for the same sentence on the AI path vs. the fallback path for simple, clear requests (e.g. "lower back").
- The floating button covering session players or important list content.

## Architecture (pipeline)

```
mic (SpeechTranscriber) ─┐
                         ├─► text ─► SafetyScreener ─► IntentExtractor ─► RoutinePicker ─► chat reply + Start
keyboard ────────────────┘            (deterministic)   (FM model │ keywords)  (existing code)
```

Each stage is a separate, testable unit; only `IntentExtractor` has two implementations.

### 1. Input
- Speech: Apple on-device speech recognition (`SpeechAnalyzer`/`SpeechTranscriber` on iOS 26; builder may use `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` if simpler). Must work offline.
- Locale follows the app's selected language (the app has in-app language switching).
- **Languages (Jason's decision): all four app languages — English, Spanish, French, Simplified Chinese (`AppLanguage`).** The SafetyScreener phrase lists and the keyword synonym dictionary exist for every language, each with unit tests (e.g. "dolor en el pecho" → `.urgent`, "dolor de espalda baja" → `Lower Back` + pain_relief). Chinese matching uses substring matching (no word boundaries). The screener checks the text against **all four** lists regardless of app language, so a mixed-language or mis-set phone still gets the warning.
- New Info.plist keys (via `INFOPLIST_KEY_*` build settings like the existing ones): microphone and speech-recognition usage descriptions.
- Permission denied → mic button explains and points to Settings; typing still works.

### 2. SafetyScreener (deterministic, runs first, always)
- Input: raw text. Output: `.ok`, `.concerning`, `.urgent`.
- Phrase lists (case-insensitive, simple normalisation):
  - **urgent:** chest pain, can't breathe / trouble breathing, unbearable / worst pain ever, passed out / fainted, can't move my legs, loss of bladder/bowel control.
  - **concerning:** sharp, shooting, numb/numbness, tingling, pins and needles, after a fall / accident / crash, swollen, pain that won't go away / for weeks, getting worse.
- On the AI path the model also returns a `seriousness` field; the final level is the **max** of screener and model (model can raise, never lower).
- `.urgent` → advice + "Call emergency services" button (opens dialer via `tel:` URL; never auto-dials). No "anyway" link.
- `.concerning` → advice ("worth checking with a doctor before stretching") + "I understand — show gentle stretches anyway". Choosing it builds the routine with difficulty capped at 1 and the "stop immediately if anything feels off" banner.
- Calm wording, no diagnosis.

### 3. IntentExtractor
Output shape (shared by both implementations):
```swift
struct AskIntent {
    var areas: [String]          // MuscleGroup / joint names the app already uses, e.g. ["Lower Back"]
    var goal: GoalID?            // existing GoalMeta ids: flexibility, stress_relief, pain_relief, better_breathing, wake_up, unwind
    var minutes: Int?            // "5 minutes", "quick" → nil means default
    var seriousness: Seriousness // .ok / .concerning / .urgent (AI path only; keyword path = .ok)
    var isOffTopic: Bool
}
```
- **AI path** (`SystemLanguageModel.default.availability == .available`): Foundation Models with guided generation (`@Generable`) so output is constrained to the struct; `areas` constrained to the app's known muscle/joint names. Instructions explain the catalog vocabulary. Time-boxed; on error/timeout fall back to keywords.
- **Keyword path**: a synonym dictionary of everyday words → area names ("low back", "lumbar", "lower spine" → `Lower Back`; "traps" → trapezius; "hamstring(s)"; "neck"; "tech neck"; etc.) and goal words ("pain", "sore", "ache" → pain_relief; "stress", "anxious" → stress_relief; "sleep", "wind down" → unwind; "wake up", "morning" → wake_up; "breathe", "breathing" → better_breathing; "flexible", "tight" → flexibility). Numbers + "min" → minutes.
- If neither path finds an area or goal → reply asking them to say where it hurts / what they want, with suggestion chips (e.g. "Stiff neck", "Lower back", "Can't sleep").

### 4. RoutinePicker (deterministic, reuses existing code)
- Areas → `RegionExerciseResolver(regions:exercises:)` (`Views/BodyMap/BodyMapComponents.swift`) for `direct` then `related` candidates. Already excludes breath-only exercises.
- Goal → boost exercises in the matching `GoalMeta.all` list (`Views/Exercises/ForYouSection.swift`). Goal-only requests (no area, e.g. "help me sleep") draw from the goal's list directly, which may include breathing exercises.
- Length: default ≈5 minutes / 4–6 exercises; honour `minutes` when given (fill until total ≥ target, cap ~20 min).
- **Left/Right pairs stay together** (both sides added adjacently, counted as one slot).
- Concerning-anyway mode: difficulty 1 only.
- Deterministic ordering (no randomness) so results are testable; builder may add stable variety later.
- Output: `[Exercise]` passed to `SessionPlayerView(exercises:)` on Start, same as `MiniRoutineReviewView`.

### 5. UI
- **AskButton** overlay above the tab bar in `HomeView`, bottom-right, on all five tabs; hidden while a session player, breathing session, onboarding tour, or any full-screen cover is up. Pages that scroll under it need extra bottom clearance (extend `.floatingTabBarClearance()` rather than a single inset — see existing comment in `HomeView.swift`).
- **Tap**: morphs into the ask bar with focused text field + mic; dims page behind; tap outside or swipe down to dismiss. (Don't put the `@FocusState` field inside a `.toolbar` — known crash/bug in this codebase.)
- **Press-and-hold**: starts listening, live transcript bubble, release to send, drag away to cancel. Light haptic on start.
- **Chat sheet**: user bubble, reply bubble, routine card (exercise rows with durations, L/R shown as one row "· L + R", total time, **Start**, safety note), suggestion chips when empty. Follow-up messages are treated as new requests (v1 is not a multi-turn conversation).
- Style: existing black + pastel theme (lavender/blue accent for Ask, mint for Start, coral for emergency call).
- Accessibility: VoiceOver labels for button ("Ask Dial Down"), hold-to-talk has an accessible alternative (tap → mic button).
- All new user-facing strings go through localization (String Catalog), keeping in mind `String`-typed `Text` props are not localized in this codebase.

## Constraints

- iOS 26.0 deployment target; Swift / SwiftUI / SwiftData. No new third-party dependencies.
- Fully offline. No data leaves the device.
- Tests use Swift Testing (module `BreathRelaxStretch`); SafetyScreener, keyword IntentExtractor and RoutinePicker must be unit-tested without the model.
- Must not change `AppTab` indexes (tour + many UI tests depend on them).

## Left to the builder

- Exact SwiftUI animation for the button → bar morph.
- Which iOS 26 speech API to use, as long as it's on-device and offline-capable.
- Exact phrase lists and synonym dictionary contents (starting from the above), and the Foundation Models prompt wording.
- File/type names and folder placement (suggested: `Services/Ask/` for pipeline, `Views/Ask/` for UI).

## Calls I (Claude) made — please check

- Chat history is not saved; follow-ups are fresh requests (no multi-turn memory in v1).
- Default routine ≈5 min, 4–6 exercises; cap ~20 min.
- AI can raise the safety level but never lower the deterministic screener's.
- Ask button is hidden during sessions/tour/full-screen covers.
- "Show gentle stretches anyway" caps difficulty at 1. If fewer than 4 difficulty-1 exercises exist for the area, show the shorter routine (minimum 1); if none exist, show the advice only plus a "Browse <area> stretches" link. Never relax the cap.
- **Sided requests** ("my left hip"): the intent uses the side-neutral area for matching (both the AI's allowed vocabulary and the synonym dictionary drop Left/Right), and Left/Right pairs are still added together. The reply may mention the side ("…for your hip — do both sides, starting with the left"). Starting with the named side is allowed; dropping the other side is not.
- **Area + goal**: the goal only **reorders** the area's candidates (goal-list exercises first, then the resolver's `direct`, then `related`). It never pulls in exercises from outside the area, so body-area requests never get breathing exercises. Goal-only requests (no area) use the goal's list directly.
- Saving the generated routine is out of scope for v1.
