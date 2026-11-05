import SwiftUI

/// A routine shown as rows (a Left/Right pair collapses to one row) plus Start.
struct AskRoutineCard: View {
    let routine: AskRoutine
    let onStart: () -> Void

    @Environment(\.locale) private var locale

    private var rows: [AskRoutine.Row] { routine.rows(locale: locale) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if routine.isGentle {
                Text("Stop immediately if anything feels off.")
                    .font(.luminaLabel)
                    .foregroundStyle(Color.onPastel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.pastelPeach, in: RoundedRectangle(cornerRadius: LuminaRadius.chip, style: .continuous))
                    .padding(.bottom, 8)
            }
            ForEach(rows) { row in
                HStack {
                    Text(verbatim: row.title)
                        .font(.luminaBody)
                        .foregroundStyle(Color.luminaOnSurface)
                    Spacer(minLength: 8)
                    Text(verbatim: Self.format(row.seconds))
                        .font(.luminaBody.monospacedDigit())
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                }
                .padding(.vertical, 9)
                Divider().overlay(Color.luminaOutline)
            }
            Button(action: onStart) {
                Label("Start", systemImage: "play.fill")
                    .font(.luminaCardTitle)
                    .foregroundStyle(Color.onPastel)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.pastelMint, in: RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .accessibilityIdentifier("ask.start")
            Text("Stop if anything hurts sharply.")
                .font(.luminaCaption)
                .foregroundStyle(Color.luminaOnSurfaceVariant)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
        .luminaCard()
    }

    static func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension AskRoutine {
    struct Row: Identifiable, Equatable {
        let id: UUID
        let title: String
        let seconds: Int
    }

    /// Display rows: an adjacent Left/Right pair collapses to one "<name> · L + R" row.
    func rows(locale: Locale = .current) -> [Row] {
        var result: [Row] = []
        var i = 0
        while i < exercises.count {
            let current = exercises[i]
            if i + 1 < exercises.count, Self.isPair(current, exercises[i + 1]) {
                let name = RoutinePicker.pairKey(current.name)
                let title = String(localized: LocalizedStringResource("\(name) · L + R", locale: locale))
                result.append(Row(id: current.uuid, title: title,
                                  seconds: current.durationSeconds + exercises[i + 1].durationSeconds))
                i += 2
            } else {
                result.append(Row(id: current.uuid, title: current.name, seconds: current.durationSeconds))
                i += 1
            }
        }
        return result
    }

    private static func isPair(_ a: Exercise, _ b: Exercise) -> Bool {
        RoutinePicker.pairKey(a.name) != a.name && RoutinePicker.pairKey(b.name) != b.name
            && a.name.hasPrefix("Left ") != b.name.hasPrefix("Left ")
            && RoutinePicker.pairKey(a.name) == RoutinePicker.pairKey(b.name)
    }
}
