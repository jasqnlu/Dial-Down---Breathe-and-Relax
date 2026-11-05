import SwiftUI

// MARK: - ExercisesTabView
//
// The Exercises tab: one title row with an Areas / Body switch, over either
// the bubble-map library (ExerciseListView) or the 3D body map
// (BodyMapView). Body used to be its own tab; it moved here so the bottom
// bar could drop to five tabs.
//
// Both views keep their own NavigationStack and state. The body map is only
// built the first time it's shown (the 3D scene is heavy), then kept alive
// so flipping back is instant and keeps its zoom and rotation.

struct ExercisesTabView: View {
    @AppStorage(ExercisesMode.storageKey) private var modeRaw = ExercisesMode.areas.rawValue
    @EnvironmentObject private var tourCoordinator: TourCoordinator
    @State private var hasShownBody = false
    /// The view the user had before the tour flipped the switch, restored
    /// once the tour leaves the Exercises section (the choice is saved, so
    /// otherwise the tour would leave Exercises stuck on Body).
    @State private var modeBeforeTour: ExercisesMode?

    private var mode: Binding<ExercisesMode> {
        Binding(
            get: { ExercisesMode(rawValue: modeRaw) ?? .areas },
            set: { modeRaw = $0.rawValue }
        )
    }

    var body: some View {
        let current = mode.wrappedValue
        ZStack {
            ExerciseListView(mode: mode)
                .environment(\.exercisesViewIsVisible, current == .areas)
                .opacity(current == .areas ? 1 : 0)
                .allowsHitTesting(current == .areas)
                .accessibilityHidden(current != .areas)

            if hasShownBody || current == .body {
                BodyMapView(mode: mode)
                    .environment(\.exercisesViewIsVisible, current == .body)
                    .opacity(current == .body ? 1 : 0)
                    .allowsHitTesting(current == .body)
                    .accessibilityHidden(current != .body)
                    .onAppear { hasShownBody = true }
            }
        }
        .onAppear { followTour(tourCoordinator.currentStep?.id) }
        .onChange(of: tourCoordinator.currentStep?.id) { _, id in followTour(id) }
        .onChange(of: tourCoordinator.isActive) { _, _ in followTour(tourCoordinator.currentStep?.id) }
        .onChange(of: modeRaw) { _, raw in
            // The tour's "Switch to the Body" step waits for this tap.
            if raw == ExercisesMode.body.rawValue {
                tourCoordinator.notifyInteraction(id: "exercises.modeSwitch")
            }
        }
    }

    /// The tour's Exercises section starts on Areas, then walks through the
    /// body map's tap-a-sore-spot steps — flip the switch to match, and put
    /// it back the way the user had it once the tour moves on or ends.
    private func followTour(_ stepID: String?) {
        let id = tourCoordinator.isActive ? stepID : nil
        let tourMode: ExercisesMode?
        if id?.hasPrefix("exercises.") == true {
            // Search, bubbles, and the switch step itself start on Areas —
            // the switch step then waits for the user to tap Body.
            tourMode = .areas
        } else if id?.hasPrefix("bodymap.") == true {
            tourMode = .body
        } else {
            tourMode = nil
        }

        if let tourMode {
            if modeBeforeTour == nil { modeBeforeTour = mode.wrappedValue }
            mode.wrappedValue = tourMode
        } else if let previous = modeBeforeTour {
            mode.wrappedValue = previous
            modeBeforeTour = nil
        }
    }
}

// MARK: - Visibility

/// Whether this half of the Exercises tab is the one showing. The hidden half
/// stays mounted (opacity 0), and `.accessibilityHidden` doesn't reach inside
/// its NavigationStack, so its controls stay in the accessibility tree. The
/// shared `PickingBar` reads this and draws nothing in the hidden half.
private struct ExercisesViewIsVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var exercisesViewIsVisible: Bool {
        get { self[ExercisesViewIsVisibleKey.self] }
        set { self[ExercisesViewIsVisibleKey.self] = newValue }
    }
}

// MARK: - Title row

/// "Exercises" large title + the Areas / Body switch. Shared by both views so
/// the header doesn't jump when switching.
struct ExercisesTitleRow: View {
    @Binding var mode: ExercisesMode
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Exercises")
                    .font(.luminaDisplay)
                    .tracking(-0.6)
                    .foregroundStyle(Color.luminaOnSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.luminaCaption)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                }
            }
            Spacer(minLength: 0)
            ExercisesModeSwitch(mode: $mode)
        }
    }
}

/// Pill-shaped two-option switch: white capsule on the selected side.
struct ExercisesModeSwitch: View {
    @Binding var mode: ExercisesMode
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            option(.areas, title: "Areas", icon: "circle.grid.2x2.fill")
            option(.body, title: "Body", icon: "figure.stand")
        }
        .padding(3)
        .background(Color.luminaCardFill, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.luminaHairline, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Exercises view")
        .tourAnchor("exercises.modeSwitch")
    }

    private func option(_ value: ExercisesMode, title: LocalizedStringKey, icon: String) -> some View {
        let isOn = mode == value
        return Button {
            guard !isOn else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { mode = value }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.luminaLabel)
            }
            .foregroundStyle(isOn ? Color.luminaOnPrimary : Color.luminaOnSurfaceVariant)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background {
                if isOn {
                    Capsule()
                        .fill(Color.luminaPrimary)
                        .matchedGeometryEffect(id: "modeSelection", in: ns)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("exercisesMode.\(value.rawValue)")
    }
}

#Preview {
    ExercisesTabView()
        .environmentObject(TourCoordinator())
        .environmentObject(ExercisePickingSession())
}
