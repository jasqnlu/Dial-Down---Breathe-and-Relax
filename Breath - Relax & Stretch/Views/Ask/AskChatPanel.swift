import SwiftData
import SwiftUI

/// The Ask Dial Down chat, shown as a semi-transparent side panel or full screen
/// (see `AskPanelMode`). A tray at the top holds the routine the chat is building;
/// it fills in live as the user asks, and offers Customize and Start.
struct AskChatPanel: View {
    let model: AskChatModel
    @Binding var mode: AskPanelMode
    let speech: SpeechInput
    let voiceIssue: SpeechUnavailableReason?
    /// Shows the mic button when set (wired up by the caller).
    var onMicTap: (() -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil
    /// Called when Start is tapped, before the player opens
    /// (the caller stops any listening it started).
    var onStart: (() -> Void)? = nil

    @Query private var catalog: [Exercise]
    @State private var text = ""
    @State private var playing: PlayableRoutine?
    @State private var customizing = false
    /// Set by Customize's Start; the player opens once Customize has gone away.
    @State private var startAfterCustomize = false
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFull: Bool { mode == .full }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.draft.isEmpty {
                tray
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    // Not lazy: a chat is short, and a LazyVStack scrolled while the
                    // panel resizes for the keyboard can loop layout.
                    VStack(alignment: .leading, spacing: 12) {
                        if model.messages.isEmpty { chips }
                        ForEach(model.messages) { message in
                            messageView(message).id(message.id)
                        }
                        if model.isThinking {
                            ProgressView().padding(.leading, 8).id("thinking")
                        }
                    }
                    .padding(isFull ? 16 : 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.isThinking) {
                    if model.isThinking { proxy.scrollTo("thinking", anchor: .bottom) }
                }
                .onChange(of: model.messages) {
                    if let last = model.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            voiceStatus
            inputRow
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85),
                   value: model.draft.exercises.map(\.uuid))
        .onChange(of: model.pendingDraft) {
            // Dictation that finished while a reply was being worked out.
            guard let words = model.takePendingDraft() else { return }
            text = text.isEmpty ? words : text + " " + words
        }
        .sheet(isPresented: $customizing, onDismiss: {
            // Customize must be fully gone before the player can present.
            if startAfterCustomize {
                startAfterCustomize = false
                start()
            }
        }) {
            customizeView
        }
        .fullScreenCover(item: $playing) { item in
            SessionPlayerView(exercises: item.routine.exercises,
                              durationOverrides: item.routine.durationOverrides)
        }
    }

    private struct PlayableRoutine: Identifiable {
        let id = UUID()
        let routine: AskRoutine
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.pastelLavender)
            Text("Ask Dial Down")
                .font(.luminaCardTitle)
                .accessibilityIdentifier("ask.sheet")
            Spacer()
            headerButton("minus", label: "Shrink", id: "ask.shrink") { mode = .pill }
            headerButton(isFull ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                         label: isFull ? "Exit full screen" : "Full screen", id: "ask.resize") {
                mode = mode.toggledSize
            }
            headerButton("xmark", label: "Close", id: "ask.close") { mode = .closed }
        }
        .foregroundStyle(Color.luminaOnSurface)
        .padding(.horizontal, isFull ? 16 : 12)
        .padding(.top, isFull ? 16 : 12)
    }

    private func headerButton(_ symbol: String, label: LocalizedStringKey, id: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.luminaOnSurfaceVariant)
                .frame(width: 30, height: 30)
                .background(Color.luminaContainer, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    // MARK: - Routine tray

    private var tray: some View {
        let routine = model.draft.routine
        let rows = routine.rows(locale: locale)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your routine")
                    .font(.luminaLabel)
                    .foregroundStyle(Color.luminaOnSurface)
                Spacer()
                Text("\(rows.count) exercises · \(AskRoutineCard.format(routine.totalSeconds))")
                    .font(.luminaCaption.monospacedDigit())
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                    .accessibilityIdentifier("ask.trayTotal")
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            trayChip(index: index + 1, row: row)
                                .id(row.id)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                }
                .onChange(of: rows.last?.id) { _, last in
                    if let last { proxy.scrollTo(last, anchor: .trailing) }
                }
            }
            HStack(spacing: 8) {
                Button { customizing = true } label: {
                    Label("Customize", systemImage: "slider.horizontal.3")
                        .font(.luminaLabel)
                        .foregroundStyle(Color.luminaOnSurface)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color.luminaContainer, in: RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ask.customize")
                Button { start() } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.luminaLabel)
                        .foregroundStyle(Color.onPastel)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color.pastelMint, in: RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ask.start")
            }
            if model.draft.isGentle {
                Text("Stop immediately if anything feels off.")
                    .font(.luminaCaption)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
            }
        }
        .padding(12)
        .background(Color.luminaCardFill.opacity(0.85),
                    in: RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ask.tray")
    }

    private func trayChip(index: Int, row: AskRoutine.Row) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: "\(index)")
                .font(.luminaCaption.monospacedDigit().weight(.bold))
                .foregroundStyle(Color.onPastel)
                .frame(width: 18, height: 18)
                .background(Color.pastelLavender, in: Circle())
            Text(verbatim: row.title)
                .font(.luminaCaption)
                .foregroundStyle(Color.luminaOnSurface)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 130, alignment: .leading)
            Text(verbatim: AskRoutineCard.format(row.seconds))
                .font(.luminaCaption.monospacedDigit())
                .foregroundStyle(Color.luminaOnSurfaceVariant)
        }
        .padding(.leading, 5).padding(.trailing, 10).padding(.vertical, 5)
        .background(Color.luminaContainer, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var customizeView: some View {
        CustomizeRoutineView(
            title: LocalizedStringResource("Your routine").resolved(in: locale),
            exercises: model.draft.exercises,
            isPinned: false,
            showsPinToggle: false,
            primaryActionLabel: LocalizedStringResource("Start").resolved(in: locale),
            showsAddExercisesButton: false,
            initialDurationOverrides: model.draft.durationOverrides,
            onAddMore: { exercises, overrides in
                model.customize(exercises: exercises, durationOverrides: overrides)
            }
        ) { _, exercises, _, overrides in
            model.customize(exercises: exercises, durationOverrides: overrides)
            startAfterCustomize = true
        }
    }

    private func start() {
        guard !model.draft.isEmpty else { return }
        onStart?()
        playing = PlayableRoutine(routine: model.draft.routine)
    }

    // MARK: - Messages

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Stiff neck")
                chip("Lower back")
                chip("Can't sleep")
                chip("Tight hips")
            }
        }
    }

    private func chip(_ key: LocalizedStringResource) -> some View {
        Button { submit(key.resolved(in: locale)) } label: {
            Text(key)
                .font(.luminaLabel)
                .foregroundStyle(Color.luminaOnSurface)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.luminaCardFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.isThinking)
    }

    @ViewBuilder
    private func messageView(_ message: AskMessage) -> some View {
        switch message.role {
        case .user:
            Text(verbatim: message.text)
                .font(.luminaBody)
                .foregroundStyle(Color.onPastel)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.pastelLavender, in: RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, isFull ? 48 : 28)
        case .reply:
            if let reply = message.reply {
                replyView(reply, id: message.id)
            }
        }
    }

    @ViewBuilder
    private func replyView(_ reply: AskReply, id: UUID) -> some View {
        switch reply {
        case .routine(let routine, let intent):
            VStack(alignment: .leading, spacing: 10) {
                bubble { routineText(routine, intent) }
                // What this request added; the tray above starts the whole routine.
                AskRoutineCard(routine: routine)
            }
        case .safety(let level, _):
            AskSafetyCard(
                level: level,
                onGentleAnyway: model.gentleShownFor.contains(id)
                    ? nil : { model.showGentleAnyway(for: id, catalog: catalog) }
            )
        case .clarify:
            bubble { Text("Tell me where you feel it or what you'd like — for example, \"stiff neck\" or \"help me sleep\".") }
        case .offTopic:
            bubble { Text("I can help you find stretches and breathing exercises.") }
        case .noMatch:
            bubble { Text("I couldn't find stretches for that yet.") }
        case .gentleNoMatch(let intent):
            VStack(alignment: .leading, spacing: 10) {
                bubble { Text("I couldn't find gentle stretches for that.") }
                browseButton(intent)
            }
        case .draftChanged(let change):
            bubble { changeText(change) }
        case .edit:
            EmptyView()   // AskChatModel always resolves these; never stored
        }
    }

    private func changeText(_ change: AskDraftChange) -> Text {
        switch change {
        case .cleared:
            return Text("Cleared. What would you like to start with?")
        case .removed(let names):
            let list = names.formatted(.list(type: .and).locale(locale))
            return Text("Removed \(list).")
        case .swapped(let from, let to):
            return Text("Swapped \(from) for \(to).")
        case .retimed(let seconds):
            return Text("Your routine is now \(AskRoutineCard.format(seconds)) long.")
        case .nothingToChange:
            return Text("Nothing in your routine matches that.")
        }
    }

    /// Shrinks the chat and opens the Exercises tab (Areas view) via HomeView.
    private func browseButton(_ intent: AskIntent) -> some View {
        Button {
            mode = .pill
            NotificationCenter.default.post(name: .browseExercisesRequested, object: nil)
        } label: {
            Group {
                if let area = intent.areas.first {
                    Text("Browse \(area.displayName.resolved(in: locale)) stretches")
                } else {
                    Text("Browse stretches")
                }
            }
            .font(.luminaLabel)
            .foregroundStyle(Color.onPastel)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.pastelLavender, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ask.browse")
    }

    private func routineText(_ routine: AskRoutine, _ intent: AskIntent) -> Text {
        let minutes = routine.displayMinutes
        if intent.areas.isEmpty {
            return Text("Here's a gentle \(minutes)-minute routine.")
        }
        return Text("Here's a gentle \(minutes)-minute routine for your \(intent.areaList(locale: locale)).")
    }

    private func bubble(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .font(.luminaBody)
            .foregroundStyle(Color.luminaOnSurface)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.luminaCardFill, in: RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, isFull ? 48 : 16)
    }

    // MARK: - Input

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Type or tap the mic…", text: $text)
                .submitLabel(.send)
                .onSubmit { submit(text) }
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(Color.luminaCardFill, in: Capsule())
                .accessibilityIdentifier("ask.input")
            if let onMicTap {
                Button(action: onMicTap) {
                    Image(systemName: speech.state == .preparing || speech.state == .listening
                          ? "stop.fill" : "mic.fill")
                        .foregroundStyle(Color.onPastel)
                        .frame(width: 44, height: 44)
                        .background(speech.state == .preparing || speech.state == .listening
                                    ? Color.pastelMint : Color.pastelLavender, in: Circle())
                }
                .accessibilityLabel(speech.state == .preparing ? "Cancel voice setup" :
                                    speech.state == .listening ? "Stop and send" : "Dictate")
                .accessibilityIdentifier("ask.mic")
            }
        }
        .padding(isFull ? 16 : 12)
    }

    @ViewBuilder
    private var voiceStatus: some View {
        if let voiceIssue {
            VoiceIssueNote(reason: voiceIssue, openSettings: { onOpenSettings?() })
                .padding(.horizontal, 12)
        } else if speech.state == .preparing || speech.state == .listening {
            VStack(alignment: .leading, spacing: 6) {
                if speech.transcript.isEmpty {
                    Text(speech.state == .preparing ? "Getting voice ready…" : "Listening…")
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                } else {
                    Text(verbatim: speech.transcript).foregroundStyle(Color.luminaOnSurface)
                }
                if speech.state == .preparing {
                    Button("Cancel") { onMicTap?() }
                        .font(.luminaCaption)
                        .accessibilityIdentifier("ask.cancelVoice")
                } else {
                    Text("Tap the mic again to send.")
                        .font(.luminaCaption)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                }
            }
            .font(.luminaBody)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.luminaContainer, in: RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous)
                    .strokeBorder(Color.pastelMint, lineWidth: 1.5)
            )
            .padding(.horizontal, 12)
            .accessibilityIdentifier("ask.voiceStatus")
        }
    }

    private func submit(_ words: String) {
        guard !model.isThinking else { return }
        text = ""
        Task { await model.send(words, catalog: catalog) }
    }
}
