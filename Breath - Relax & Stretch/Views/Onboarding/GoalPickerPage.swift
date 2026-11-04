import SwiftUI

// MARK: - Goal Picker Page

struct GoalPickerPage: View {
    @Binding var selectedGoals: Set<String>

    private struct Goal: Identifiable {
        let id: String   // used as the key in selectedGoals
        let icon: String
        let label: LocalizedStringKey
    }

    private let goals: [Goal] = [
        Goal(id: "flexibility",      icon: "figure.flexibility", label: "Flexibility"),
        Goal(id: "stress_relief",    icon: "leaf.fill",          label: "Stress Relief"),
        Goal(id: "pain_relief",      icon: "bandage.fill",       label: "Pain Relief"),
        Goal(id: "better_breathing", icon: "wind",               label: "Better Breathing"),
    ]

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 60)

                Text("What brings you here?")
                    .font(.luminaDisplay)
                    .foregroundStyle(Color.luminaOnSurface)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("We'll personalise your experience.")
                    .font(.luminaBody)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 10)

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(goals) { goal in
                        GoalCard(
                            icon: goal.icon,
                            label: goal.label,
                            isSelected: selectedGoals.contains(goal.id)
                        ) {
                            toggleGoal(goal.id)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 36)

                Spacer(minLength: 160)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func toggleGoal(_ id: String) {
        if selectedGoals.contains(id) {
            selectedGoals.remove(id)
        } else {
            selectedGoals.insert(id)
        }
    }
}

// MARK: - Goal Card

struct GoalCard: View {
    let icon: String
    let label: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                // Pastel icon circle (stable per icon); selected tiles get
                // a white ring and a check, like the Breathe pattern tiles.
                LuminaIconBadge(systemName: icon, size: 56)
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.luminaOnPrimary)
                                .frame(width: 20, height: 20)
                                .background(Color.luminaPrimary, in: Circle())
                                .offset(x: 4, y: -4)
                        }
                    }

                Text(label)
                    .font(.luminaCardTitle)
                    .foregroundStyle(Color.luminaOnSurface)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous)
                    .fill(Color.luminaCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LuminaRadius.card, style: .continuous)
                    .strokeBorder(isSelected ? Color.luminaOnSurface : Color.luminaHairline,
                                  lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Focus Area Picker Page
//
// Signup step where the user chooses which body areas they want to train.
// Stored (by the parent, as category raw values) in `onboardingAreas` and
// used to personalise the Home "Recommended" carousel. Colour-coded to match
// the Exercises tab's node graph so the areas read as the same vocabulary.

struct FocusAreaPickerPage: View {
    @Binding var selectedAreas: Set<String>

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private static let icons: [ExerciseCategory: String] = [
        .neck: "figure.stand",
        .shoulders: "figure.arms.open",
        .chest: "lungs.fill",
        .back: "figure.walk",
        .core: "figure.core.training",
        .arms: "figure.strengthtraining.traditional",
        .hipsGlutes: "figure.flexibility",
        .legs: "figure.run",
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 60)

                Text("Where do you want to focus?")
                    .font(.luminaDisplay)
                    .foregroundStyle(Color.luminaOnSurface)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("Pick the areas you'd like to train. We'll recommend exercises for them.")
                    .font(.luminaBody)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 10)

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(ExerciseCategory.allCases) { area in
                        FocusAreaCard(
                            title: LocalizedStringKey(area.rawValue),
                            icon: Self.icons[area] ?? "figure.mind.and.body",
                            accent: area.pastel,
                            isSelected: selectedAreas.contains(area.rawValue)
                        ) {
                            toggle(area.rawValue)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 32)

                Spacer(minLength: 160)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func toggle(_ id: String) {
        if selectedAreas.contains(id) {
            selectedAreas.remove(id)
        } else {
            selectedAreas.insert(id)
        }
    }
}

// MARK: - Focus Area Card

struct FocusAreaCard: View {
    let title: LocalizedStringKey
    let icon: String
    let accent: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LuminaIconBadge(systemName: icon, tint: accent, size: 42)
                    .opacity(isSelected ? 1 : 0.85)

                Text(title)
                    .font(.luminaCardTitle)
                    .foregroundStyle(Color.luminaOnSurface)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.luminaOnPrimary)
                        .frame(width: 20, height: 20)
                        .background(Color.luminaPrimary, in: Circle())
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                    .fill(Color.luminaCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                    .strokeBorder(isSelected ? Color.luminaOnSurface : Color.luminaHairline,
                                  lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(title)
    }
}

// MARK: - Preview

#Preview("Goal Picker") {
    StatefulPreviewWrapper(Set<String>()) { binding in
        GoalPickerPage(selectedGoals: binding)
    }
}

#Preview("Focus Area Picker") {
    StatefulPreviewWrapper(Set<String>()) { binding in
        FocusAreaPickerPage(selectedAreas: binding)
    }
}

// MARK: - Preview Helper

/// Wraps a `@State` binding for preview purposes without needing a parent view.
struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initialValue: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initialValue)
        self.content = content
    }

    var body: some View { content($value) }
}
