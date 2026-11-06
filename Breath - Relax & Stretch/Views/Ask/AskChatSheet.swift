import SwiftData
import SwiftUI

struct AskChatSheet: View {
    let model: AskChatModel
    let initialText: String?
    /// Shows the mic button when set (wired up by the caller).
    var onMicTap: (() -> Void)? = nil
    /// Called when a routine's Start is tapped, before the player opens
    /// (the caller stops any listening it started).
    var onStart: (() -> Void)? = nil

    @Query private var catalog: [Exercise]
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var didSendInitial = false
    @State private var playing: PlayableRoutine?
    @Environment(\.locale) private var locale

    init(model: AskChatModel, initialText: String?,
         onMicTap: (() -> Void)? = nil, onStart: (() -> Void)? = nil) {
        self.model = model
        self.initialText = initialText
        self.onMicTap = onMicTap
        self.onStart = onStart
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.messages.isEmpty { chips }
                        ForEach(model.messages) { message in
                            messageView(message).id(message.id)
                        }
                        if model.isThinking {
                            ProgressView().padding(.leading, 8).id("thinking")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.isThinking) {
                    if model.isThinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
                }
                .onChange(of: model.messages) {
                    if let last = model.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            inputRow
        }
        .onChange(of: model.pendingDraft) {
            // Dictation that finished while a reply was being worked out.
            guard let words = model.takePendingDraft() else { return }
            draft = draft.isEmpty ? words : draft + " " + words
        }
        .background(Color.luminaSurface.ignoresSafeArea())
        .task {
            guard !didSendInitial, let initialText, !initialText.isEmpty else { return }
            didSendInitial = true
            await model.send(initialText, catalog: catalog)
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

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Text("Ask Dial Down").font(.luminaCardTitle)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                    .frame(width: 32, height: 32)
                    .background(Color.luminaContainer, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .foregroundStyle(Color.luminaOnSurface)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

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
                .padding(.leading, 48)
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
                AskRoutineCard(routine: routine) {
                    onStart?()
                    playing = PlayableRoutine(routine: routine)
                }
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

    /// Closes the sheet and opens the Exercises tab (Areas view) via HomeView.
    private func browseButton(_ intent: AskIntent) -> some View {
        Button {
            dismiss()
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
            .padding(.trailing, 48)
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Type or tap the mic…", text: $draft)
                .submitLabel(.send)
                .onSubmit { submit(draft) }
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(Color.luminaCardFill, in: Capsule())
                .accessibilityIdentifier("ask.input")
            if let onMicTap {
                Button(action: onMicTap) {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(Color.onPastel)
                        .frame(width: 44, height: 44)
                        .background(Color.pastelLavender, in: Circle())
                }
                .accessibilityLabel("Dictate")
                .accessibilityIdentifier("ask.mic")
            }
        }
        .padding(16)
    }

    private func submit(_ text: String) {
        guard !model.isThinking else { return }
        draft = ""
        Task { await model.send(text, catalog: catalog) }
    }
}
