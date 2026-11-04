import SwiftUI
import SwiftData
import OSLog

// MARK: - PremadeRoutinesView
// Curated single-session routine templates. Tapping one opens
// RoutineBuilderView pre-seeded with the template's name and exercises —
// see PremadeRoutine's doc comment. Nothing is saved until the user hits
// Save there.

struct PremadeRoutinesView: View {
    @Query private var exercises: [Exercise]
    @State private var selectedRoutine: PremadeRoutine?

    var body: some View {
        List(PremadeRoutine.all) { routine in
            let meta = metaInfo(for: routine)
            Button {
                selectedRoutine = routine
            } label: {
                PremadeRoutineRow(routine: routine, meta: meta)
            }
            .buttonStyle(.plain)
            .disabled(meta == nil)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.luminaSurface)
        .navigationTitle("Premade Routines")
        .navigationBarTitleDisplayMode(.inline)
        .floatingTabBarClearance()
        .sheet(item: $selectedRoutine) { routine in
            PremadeRoutineCustomizeSheet(routine: routine, exercises: exercises)
        }
    }

    /// The raw (count, minutes) behind the row's meta line, or nil if the
    /// routine currently resolves to zero exercises. Kept as data rather
    /// than a formatted String so the call site can render a `Text` literal
    /// that participates in localization — see PremadeRoutineRow.
    private func metaInfo(for routine: PremadeRoutine) -> (count: Int, minutes: Int)? {
        let resolved = routine.resolvedExercises(in: exercises)
        guard !resolved.isEmpty else { return nil }
        let totalSecs = resolved.reduce(0) { $0 + $1.durationSeconds }
        let mins = max(1, Int((Double(totalSecs) / 60).rounded()))
        return (resolved.count, mins)
    }
}

/// Opens a premade routine in the same Customize screen Today uses
/// (summary tiles, roomy exercise rows, white bottom button), in its
/// "name it and save" mode. Shared by Today's premade row and the
/// Premade Routines list. Nothing is saved until "Save Routine".
///
/// "Add Exercises" is hidden: Customize's cross-tab picker always returns
/// to Today's own Customize (Begin, not Save), so it can't round-trip here.
/// Exercises can still be added later by editing the saved routine.
struct PremadeRoutineCustomizeSheet: View {
    let routine: PremadeRoutine
    let exercises: [Exercise]

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        CustomizeRoutineView(
            title: routine.title,
            exercises: routine.resolvedExercises(in: exercises),
            isPinned: false,
            showsNameField: true,
            initialName: routine.title,
            showsPinToggle: false,
            primaryActionLabel: "Save Routine",
            primaryActionIcon: "checkmark",
            showsAddExercisesButton: false
        ) { name, picked, _, durationOverrides in
            save(name: name, exercises: picked, durationOverrides: durationOverrides)
        }
    }

    /// Same save RoutineBuilderView does for a new routine, including the
    /// "Routine Builder" badge.
    private func save(name: String, exercises: [Exercise], durationOverrides: [UUID: Int]) {
        let saved = Routine(
            name: name,
            exerciseIDs: exercises.map(\.uuid),
            exerciseDurationOverrides: durationOverrides,
            ownerID: auth.backendID
        )
        saved.insertAndQueueForSync(in: modelContext)
        if let profile = (try? modelContext.fetch(FetchDescriptor<UserProfile>()))?.first {
            GamificationService.awardBadge("Routine Builder", to: profile)
        }
        do {
            try modelContext.save()
        } catch {
            Logger(subsystem: "com.jasonlu.breath", category: "premadeRoutine").warning("Save failed: \(error)")
        }
    }
}

private struct PremadeRoutineRow: View {
    let routine: PremadeRoutine
    let meta: (count: Int, minutes: Int)?

    var body: some View {
        HStack(spacing: 14) {
            // Same pastel as this routine's tile on Today.
            LuminaIconBadge(systemName: routine.icon,
                            tint: routine.pastel,
                            size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.title)
                    .font(.luminaCardTitle)
                    .foregroundStyle(Color.luminaOnSurface)
                Text(routine.summary)
                    .font(.luminaCaption)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                    .lineLimit(2)
                if let meta {
                    Text("\(meta.count) exercise\(meta.count == 1 ? "" : "s") · \(meta.minutes) min")
                        .font(.luminaCaption)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                } else {
                    Text("Unavailable")
                        .font(.luminaCaption)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.luminaOnSurfaceVariant)
                .frame(width: 28, height: 28)
                .background(Color.luminaContainer, in: Circle())
                .opacity(meta == nil ? 0 : 1)
                .accessibilityHidden(true)
        }
        .luminaCard(padding: 14)
    }
}

#Preview {
    NavigationStack {
        PremadeRoutinesView()
    }
    .modelContainer(for: [Exercise.self, Routine.self], inMemory: true)
}
