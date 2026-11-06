import SwiftUI

/// A routine shown as rows (a Left/Right pair collapses to one row), plus Start
/// when `onStart` is set.
struct AskRoutineCard: View {
    let routine: AskRoutine
    var onStart: (() -> Void)? = nil

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
            if let onStart {
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
            }
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
    func rows(locale: Locale) -> [Row] {
        RoutinePicker.slots(of: exercises).map { slot in
            let seconds = slot.reduce(0) { $0 + self.seconds(for: $1) }
            guard slot.count == 2 else {
                return Row(id: slot[0].uuid, title: slot[0].name, seconds: seconds)
            }
            let name = RoutinePicker.pairKey(slot[0].name)
            let title = String(localized: LocalizedStringResource("\(name) · L + R", locale: locale))
            return Row(id: slot[0].uuid, title: title, seconds: seconds)
        }
    }
}
