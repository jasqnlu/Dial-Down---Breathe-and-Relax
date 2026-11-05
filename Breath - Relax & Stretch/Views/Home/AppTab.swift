import Foundation

/// The bottom tab bar's tabs, in display order. The raw value is the index
/// `HomeView` and `CustomTabBar` use for `selectedTab`, and the value stored
/// in `ExercisePickingSession.Context.originTab` and `TourStep.tabIndex`.
///
/// Always refer to tabs through this enum, never a bare number — the Body
/// tab was folded into Exercises (Areas / Body switch), which shifted every
/// index after it.
enum AppTab: Int, CaseIterable {
    case today = 0
    case exercises
    case breathe
    case routines
    case profile
}

/// The two views inside the Exercises tab. Stored in `@AppStorage` under
/// `ExercisesMode.storageKey` so the tab reopens on the user's last choice,
/// and so other screens (and `-exercisesMode body` launch arguments in UI
/// tests) can pick one.
enum ExercisesMode: String {
    case areas
    case body

    static let storageKey = "exercisesMode"
}
