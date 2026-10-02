import SwiftUI
import SwiftData
import os

// MARK: - ImportRoutineView
// Confirmation sheet shown when the app is opened via a shared `breath://routine`
// link. Exercises are matched by name against the local catalog — any that
// don't exist locally are skipped and called out.

struct ImportRoutineView: View {
    let payload: RoutineSharePayload
    let onDismiss: () -> Void

    @Query private var exercises: [Exercise]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthManager

    private var matched: [Exercise] {
        let byName = Dictionary(uniqueKeysWithValues: exercises.map { ($0.name, $0) })
        return payload.exerciseNames.compactMap { byName[$0] }
    }

    private var missingCount: Int { payload.exerciseNames.count - matched.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.luminaPrimary)
                    .padding(.top, 24)

                Text(payload.name)
                    .font(.luminaTitle)
                    .foregroundStyle(Color.luminaOnSurface)
                    .multilineTextAlignment(.center)

                Text("\(matched.count) of \(payload.exerciseNames.count) exercises found on your device")
                    .font(.luminaSubheadline)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)

                if missingCount > 0 {
                    Text("\(missingCount) exercise\(missingCount == 1 ? "" : "s") couldn't be matched and will be skipped.")
                        .font(.luminaCaption)
                        .foregroundStyle(Color.luminaOrange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                List(matched) { exercise in
                    Text(exercise.name)
                        .font(.luminaBody)
                        .foregroundStyle(Color.luminaOnSurface)
                        .listRowBackground(Color.luminaCardFill)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                Button(action: saveRoutine) {
                    Text("Add to My Routines")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LuminaPillButtonStyle())
                .disabled(matched.isEmpty)
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color.luminaSurface.ignoresSafeArea())
            .navigationTitle("Shared Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                }
            }
        }
    }

    private func saveRoutine() {
        let routine = Routine(name: payload.name, exerciseIDs: matched.map { $0.uuid }, ownerID: auth.backendID)
        routine.insertAndQueueForSync(in: modelContext)
        do {
            try modelContext.save()
        } catch {
            Logger(subsystem: "com.jasonlu.breath", category: "importRoutine").warning("Save failed: \(error)")
        }
        onDismiss()
    }
}
