import SwiftUI

/// A routine shown as rows (a Left/Right pair collapses to one row) plus Start.
struct AskRoutineCard: View {
    let routine: AskRoutine
    let onStart: () -> Void

    struct Row: Identifiable {
        let id: UUID
        let title: String
        let seconds: Int
    }

    var rows: [Row] {
        var result: [Row] = []
        var i = 0
        let list = routine.exercises
        while i < list.count {
            let current = list[i]
            if i + 1 < list.count, Self.isPair(current, list[i + 1]) {
                let name = RoutinePicker.pairKey(current.name)
                result.append(Row(id: current.uuid,
                                  title: String(localized: "\(name) · L + R"),
                                  seconds: current.durationSeconds + list[i + 1].durationSeconds))
                i += 2
            } else {
                result.append(Row(id: current.uuid, title: current.name, seconds: current.durationSeconds))
                i += 1
            }
        }
        return result
    }

    private static func isPair(_ a: Exercise, _ b: Exercise) -> Bool {
        let sides = Set([a.name.hasPrefix("Left ") ? "L" : (a.name.hasPrefix("Right ") ? "R" : ""),
                         b.name.hasPrefix("Left ") ? "L" : (b.name.hasPrefix("Right ") ? "R" : "")])
        return sides == ["L", "R"] && RoutinePicker.pairKey(a.name) == RoutinePicker.pairKey(b.name)
    }

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
