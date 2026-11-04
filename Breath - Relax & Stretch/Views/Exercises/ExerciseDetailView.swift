import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise
    @State private var showingPlayer = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // ── Meta chips ──────────────────────────────────────────────
                HStack(spacing: 16) {
                    StatChip(icon: "clock",     label: exercise.durationFormatted)
                    StatChip(icon: "chart.bar", label: difficultyLabel)
                    // Category chip — static blue chip look per the mock's
                    // "Flexibility"-style pill (exercise.type is the category).
                    Text(exercise.type.rawValue)
                        .font(.luminaLabel)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.pastelBlue)
                        .foregroundStyle(Color.onPastel)
                        .clipShape(Capsule())
                        .accessibilityLabel(exercise.type.rawValue)
                }
                .padding(.horizontal)

                // ── Safety caution (only when the exercise has one) ─────────
                if let caution = exercise.caution, !caution.isEmpty {
                    CautionCard(text: caution)
                        .padding(.horizontal)
                }

                // ── Media: local demo video, when available ──────────────────
                ExerciseMediaCard(exercise: exercise)

                Divider()

                // ── Target body parts ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    Text("Targets")
                        .font(.luminaCardTitle)
                        .padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(exercise.targetBodyParts, id: \.self) { part in
                                // Body-area chip — static orange chip look per
                                // the mock's "Lower Body"-style pill.
                                Text(part)
                                    .font(.luminaLabel)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.luminaContainer)
                                    .foregroundStyle(Color.luminaOnSurface)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                Divider()

                // ── Step-by-step instructions ────────────────────────────────
                VStack(alignment: .leading, spacing: 14) {
                    Text("Instructions")
                        .font(.luminaCardTitle)
                        .padding(.horizontal)
                    ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            // Pastel number circle, same as Today's hero list.
                            Text("\(index + 1)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .frame(width: 28, height: 28)
                                .background(Color.pastels[index % Color.pastels.count])
                                .foregroundStyle(Color.onPastel)
                                .clipShape(Circle())
                            Text(step)
                                .font(.luminaBody)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .luminaCard()
                        .padding(.horizontal)
                    }
                }

                // ── Global medical disclaimer ───────────────────────────────
                MedicalDisclaimerNote()
                    .padding(.horizontal)
                    .padding(.top, 8)

                Spacer(minLength: 80)
            }
            .padding(.vertical)
        }
        .background(Color.luminaSurface)
        .navigationTitle(exercise.name)
        .safeAreaInset(edge: .bottom) {
            // Full-width white bar on a fade, like Customize's bottom button.
            Button {
                showingPlayer = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Start Exercise")
                    Text("· \(exercise.durationFormatted)")
                        .foregroundStyle(Color.luminaOnPrimary.opacity(0.55))
                }
                .font(.luminaCardTitle)
                .foregroundStyle(Color.luminaOnPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.luminaPrimary, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start Exercise")
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 8)
            .background(
                LinearGradient(colors: [Color.luminaSurface.opacity(0), Color.luminaSurface],
                               startPoint: .top, endPoint: .init(x: 0.5, y: 0.4))
            )
        }
        // After the CTA inset so the clearance band sits below it: the
        // docked button then rests above the floating tab bar, not behind it.
        .floatingTabBarClearance()
        .sheet(isPresented: $showingPlayer) {
            SessionPlayerView(exercises: [exercise])
        }
    }

    var difficultyLabel: String {
        switch exercise.difficulty {
        case 1: return "Easy"
        case 2: return "Medium"
        case 3: return "Hard"
        default: return "–"
        }
    }
}

// MARK: - Stat chip

struct StatChip: View {
    let icon: String
    let label: String

    var body: some View {
        Label(label, systemImage: icon)
            .font(.luminaCaption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.luminaContainer)
            .clipShape(RoundedRectangle(cornerRadius: LuminaRadius.tag))
            .accessibilityLabel(label)
    }
}
