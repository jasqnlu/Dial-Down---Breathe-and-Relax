import SwiftUI

/// What (if anything) sits in a tile's bottom-trailing corner. `.none` is
/// plain browsing (search results, category groups) — the whole tile is
/// one tap target going to `onTap`. `.add` is used by both the Customize
/// add-mode flow and Body Map's mini-routine builder: the corner circle is
/// its own tap target (`onBadgeTap`), independent of the tile's main
/// `onTap` (which, per call site, is either "go to detail" or "start this
/// exercise now" — ExerciseGridTile itself doesn't know or care which).
enum ExerciseGridBadge: Equatable {
    case none
    case add(isSelected: Bool)
}

/// The one exercise-list visual used everywhere an exercise list renders:
/// Exercises tab search results, a category group screen, and Body Map's
/// region list. Replaces the old ExerciseRow (text + a video-or-gray-icon
/// thumbnail) at all three call sites.
struct ExerciseGridTile: View {
    let exercise: Exercise
    var badge: ExerciseGridBadge = .none
    var onTap: () -> Void
    var onBadgeTap: (() -> Void)? = nil

    var body: some View {
        Button(action: onTap) {
            ExerciseTileCard(exercise: exercise) { badgeView }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(exercise.name), \(exercise.durationFormatted), \(exercise.type.rawValue)")
        // Stable handle for UI tests (the visible label is seed-data
        // dependent); has no effect on VoiceOver, which reads the label above.
        .accessibilityIdentifier("exerciseGridTile")
    }

    @ViewBuilder
    private var badgeView: some View {
        switch badge {
        case .none:
            EmptyView()
        case .add(let isSelected):
            Button {
                onBadgeTap?()
            } label: {
                Image(systemName: isSelected ? "checkmark" : "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isSelected ? Color.luminaOnPrimary : Color.luminaOnSurfaceVariant)
                    .frame(width: 26, height: 26)
                    .background(isSelected ? Color.luminaPrimary : Color.luminaContainer, in: Circle())
            }
            .padding(8)
            .accessibilityLabel(isSelected ? "Remove \(exercise.name)" : "Add \(exercise.name)")
        }
    }
}

// MARK: - Shared tile card

/// The one exercise tile look, used by every exercise list in the app
/// (search results, category groups, Body Map's region list, Today's "For
/// You" row) so tiles are the same size everywhere: fixed-size artwork, a
/// title that always reserves two lines, and a one-line meta row. Without
/// the reserved lines, a one-line name ("Bridge Pose") made a shorter tile
/// than its two-line neighbor.
struct ExerciseTileCard<Corner: View>: View {
    let exercise: Exercise
    @ViewBuilder var corner: () -> Corner

    /// Artwork edge length (square).
    static var artSize: CGFloat { 112 }
    /// Tile width where tiles sit in a horizontal row instead of a 2-column
    /// grid — matches a grid column on a standard-width iPhone.
    static var rowWidth: CGFloat { 172 }

    var body: some View {
        let category = ExerciseCategory.primary(for: exercise.targetBodyParts)
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                ExerciseArt(exercise: exercise, category: category, size: Self.artSize)
                    .frame(maxWidth: .infinity)
                corner()
            }
            .padding(.bottom, 4)

            Text(exercise.name)
                .font(.luminaCardTitle)
                .foregroundStyle(Color.luminaOnSurface)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)

            Text("\(exercise.durationFormatted) · \(exercise.type.rawValue)")
                .font(.luminaCaption)
                .foregroundStyle(Color.luminaOnSurfaceVariant)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luminaCard(padding: 0)
    }
}

extension ExerciseTileCard where Corner == EmptyView {
    init(exercise: Exercise) {
        self.init(exercise: exercise) { EmptyView() }
    }
}
