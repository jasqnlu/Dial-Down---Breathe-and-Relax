import SwiftData
import SwiftUI
import UIKit

/// The floating "Ask Dial Down" entry point. Rests as a small circle above the
/// tab bar; **tap** morphs it into a type-or-talk bar, **press and hold** listens
/// (release sends, slide away cancels). Sending opens `AskChatSheet`.
///
/// Lives in a full-screen overlay above `CustomTabBar` (see `HomeView`). While
/// resting only the circle takes touches, so the pages underneath stay usable.
struct AskButton: View {
    static let size: CGFloat = 50
    /// Gap between the tab bar's clearance zone and the button.
    static let spacing: CGFloat = 16
    /// Extra bottom space a page keeps clear for the resting button.
    static let clearance: CGFloat = size + spacing

    /// How long a press must last before it becomes hold-to-talk.
    private static let holdDelay: Duration = .milliseconds(300)
    /// Dragging this far from the press point while listening cancels it.
    private static let cancelDistance: CGFloat = 60

    private enum Mode: Equatable {
        case resting
        /// The ask bar with the keyboard up (mic in the bar toggles listening).
        case typing
        /// Press-and-hold listening from the resting button.
        case holding
    }

    /// One chat presentation: a fresh conversation seeded with the user's words.
    private struct ChatRequest: Identifiable {
        let id = UUID()
        let text: String
        let model: AskChatModel
    }

    @Query private var catalog: [Exercise]
    @AppStorage(AppLanguage.storageKey) private var languageRaw = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var speech = SpeechInput()
    @State private var mode: Mode = .resting
    @State private var draft = ""
    @State private var chat: ChatRequest?
    /// Why voice failed most recently; shown until the user moves on.
    @State private var voiceIssue: SpeechUnavailableReason?
    @State private var holdTask: Task<Void, Never>?
    @State private var pressStart: Date?
    @State private var holdCount = 0
    @GestureState private var isPressing = false
    @FocusState private var fieldFocused: Bool
    @Namespace private var ns

    private var speechLocale: Locale {
        AppLanguage(stored: languageRaw).locale ?? Locale.current
    }

    private var isListening: Bool { speech.state == .listening }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if mode != .resting || voiceIssue != nil {
                backdrop
            }
            if mode == .typing {
                typingLayer
            } else {
                restingLayer
            }
        }
        .accessibilityAction(.escape) { collapse() }
        .onChange(of: speech.state) { _, state in
            if case .unavailable(let reason) = state { voiceIssue = reason }
        }
        .onChange(of: speech.transcript) { _, text in
            // The bar's field mirrors what the mic hears.
            if mode == .typing, isListening { draft = text }
        }
        .onChange(of: isPressing) { _, pressing in
            // Fires for release *and* system-cancelled touches (e.g. a permission alert).
            if !pressing { pressEnded() }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: holdCount)
        .sheet(item: $chat, onDismiss: { speech.cancel(); voiceIssue = nil }) { request in
            AskChatSheet(model: request.model, initialText: request.text) {
                toggleSheetMic(model: request.model)
            }
            .overlay(alignment: .bottom) { sheetVoiceStatus }
            .presentationDetents([.large])
            .accessibilityIdentifier("ask.sheet")
        }
    }

    // MARK: - Layers

    private var backdrop: some View {
        Color.black.opacity(0.45)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { collapse() }
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    /// The resting circle (and, while holding, the live transcript beside it).
    /// Ignores the keyboard so it doesn't ride up over other screens' keyboards.
    private var restingLayer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if mode == .holding || voiceIssue != nil {
                Group {
                    if let voiceIssue {
                        VoiceIssueNote(reason: voiceIssue, openSettings: openSettings)
                    } else {
                        transcriptBubble
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            }
            restingButton
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.bottom, CustomTabBar.contentClearance + Self.spacing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .ignoresSafeArea(.keyboard)
    }

    private var restingButton: some View {
        let holding = mode == .holding
        return ZStack {
            Capsule()
                .fill(LinearGradient(colors: [.pastelLavender, .pastelBlue],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .matchedGeometryEffect(id: "askShape", in: ns)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
            Image(systemName: holding ? "mic.fill" : "sparkles")
                .font(.system(size: holding ? 24 : 20, weight: .semibold))
                .foregroundStyle(Color.onPastel)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: holding ? Self.size * 1.3 : Self.size,
               height: holding ? Self.size * 1.3 : Self.size)
        .contentShape(Circle())
        .frame(width: Self.size * 1.3, height: Self.size * 1.3, alignment: .bottomTrailing)
        .gesture(pressGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Ask Dial Down")
        .accessibilityHint("Double-tap to type. Hold to speak.")
        .accessibilityAction { expand(listening: false) }
        .accessibilityAction(named: "Speak") { expand(listening: true) }
        .accessibilityIdentifier("ask.button")
    }

    private var transcriptBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if speech.transcript.isEmpty {
                Text("Listening…")
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
            } else {
                Text(verbatim: speech.transcript)
                    .foregroundStyle(Color.luminaOnSurface)
            }
            Text("Let go to send. Slide away to cancel.")
                .font(.luminaCaption)
                .foregroundStyle(Color.luminaOnSurfaceVariant)
        }
        .font(.luminaBody)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.luminaContainer, in: RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous)
                .strokeBorder(Color.pastelMint, lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ask.transcript")
    }

    /// The expanded ask bar. Respects the keyboard safe area so it sits on top of it.
    private var typingLayer: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if let voiceIssue {
                VoiceIssueNote(reason: voiceIssue, openSettings: openSettings)
            }
            askBar
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var askBar: some View {
        HStack(spacing: 8) {
            // In content, not a toolbar: a @FocusState field in a toolbar breaks focus.
            TextField("Type or tap the mic…", text: $draft)
                .font(.luminaBody)
                .foregroundStyle(Color.luminaOnSurface)
                .tint(Color.pastelLavender)
                .focused($fieldFocused)
                .submitLabel(.send)
                .onSubmit { send(draft) }
                .padding(.leading, 18)
                .accessibilityIdentifier("ask.field")
            Button(action: toggleBarMic) {
                Image(systemName: isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.onPastel)
                    .frame(width: 40, height: 40)
                    .background(isListening ? Color.pastelMint : Color.pastelLavender, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isListening ? "Stop and send" : "Dictate")
            .accessibilityIdentifier("ask.mic")
        }
        .padding(5)
        .frame(minHeight: Self.size)
        .background {
            Capsule()
                .fill(Color.luminaContainer)
                .matchedGeometryEffect(id: "askShape", in: ns)
        }
        .overlay(Capsule().strokeBorder(isListening ? Color.pastelMint : Color.pastelLavender, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ask.bar")
        .onAppear { fieldFocused = true }
    }

    /// Listening/unavailable status floated above the chat sheet's input row.
    @ViewBuilder
    private var sheetVoiceStatus: some View {
        Group {
            if let voiceIssue {
                VoiceIssueNote(reason: voiceIssue, openSettings: openSettings)
            } else if isListening {
                VStack(alignment: .leading, spacing: 6) {
                    if speech.transcript.isEmpty {
                        Text("Listening…").foregroundStyle(Color.luminaOnSurfaceVariant)
                    } else {
                        Text(verbatim: speech.transcript).foregroundStyle(Color.luminaOnSurface)
                    }
                    Text("Tap the mic again to send.")
                        .font(.luminaCaption)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                }
                .font(.luminaBody)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.luminaContainer, in: RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous)
                        .strokeBorder(Color.pastelMint, lineWidth: 1.5)
                )
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16)
        // Clears the sheet's input row (44pt field + 16pt padding each side).
        .padding(.bottom, 80)
    }

    // MARK: - Press handling

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isPressing) { _, pressing, _ in pressing = true }
            .onChanged { value in
                if pressStart == nil {
                    pressStart = .now
                    scheduleHold()
                }
                let moved = hypot(value.translation.width, value.translation.height)
                if mode == .holding, moved > Self.cancelDistance {
                    cancelHold()
                }
            }
    }

    private func scheduleHold() {
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: Self.holdDelay)
            guard !Task.isCancelled, pressStart != nil, mode == .resting else { return }
            beginHold()
        }
    }

    private func beginHold() {
        voiceIssue = nil
        holdCount += 1
        withAnimation(animation) { mode = .holding }
        Task { await speech.start(locale: speechLocale) }
    }

    /// Slid away while holding: drop what was heard.
    private func cancelHold() {
        speech.cancel()
        withAnimation(animation) { mode = .resting }
    }

    private func pressEnded() {
        holdTask?.cancel()
        holdTask = nil
        let wasTap = pressStart.map { Date.now.timeIntervalSince($0) < 0.3 } ?? false
        pressStart = nil
        switch mode {
        case .holding:
            let text = speech.stop()
            withAnimation(animation) { mode = .resting }
            if !text.isEmpty { presentChat(text) }
        case .resting:
            if wasTap { expand(listening: false) }
        case .typing:
            break
        }
    }

    // MARK: - Actions

    private var animation: Animation? {
        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8)
    }

    private func expand(listening: Bool) {
        voiceIssue = nil
        draft = ""
        withAnimation(animation) { mode = .typing }
        if listening {
            Task { await speech.start(locale: speechLocale) }
        }
    }

    private func collapse() {
        speech.cancel()
        fieldFocused = false
        voiceIssue = nil
        draft = ""
        withAnimation(animation) { mode = .resting }
    }

    private func toggleBarMic() {
        if isListening {
            send(speech.stop())
        } else {
            voiceIssue = nil
            Task { await speech.start(locale: speechLocale) }
        }
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if !isListening { collapse() }
            return
        }
        collapse()
        presentChat(trimmed)
    }

    private func presentChat(_ text: String) {
        chat = ChatRequest(text: text, model: AskChatModel(pipeline: .live()))
    }

    private func toggleSheetMic(model: AskChatModel) {
        if isListening {
            let text = speech.stop().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            Task { await model.send(text, catalog: catalog) }
        } else {
            voiceIssue = nil
            Task { await speech.start(locale: speechLocale) }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

/// Why voice can't be used, with a way to fix it when it's a permission.
private struct VoiceIssueNote: View {
    let reason: SpeechUnavailableReason
    let openSettings: () -> Void

    private var needsSettings: Bool { reason == .micDenied || reason == .speechDenied }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch reason {
            case .micDenied:
                Text("Allow microphone access in Settings to talk to Dial Down.")
            case .speechDenied:
                Text("Allow speech recognition in Settings to talk to Dial Down.")
            case .localeUnsupported, .assetUnavailable, .audioFailed:
                Text("Voice isn't available right now — you can type instead.")
            }
            if needsSettings {
                Button("Open Settings", action: openSettings)
                    .font(.luminaLabel)
                    .foregroundStyle(Color.onPastel)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.pastelLavender, in: Capsule())
                    .buttonStyle(.plain)
            }
        }
        .font(.luminaBody)
        .foregroundStyle(Color.luminaOnSurface)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.luminaContainer, in: RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ask.voiceIssue")
    }
}
