import SwiftUI

// MARK: - Shared safety copy

enum Safety {
    /// App-wide disclaimer. Shown wherever exercises are presented.
    static let disclaimer = "This app offers general wellness and stretching guidance only — it is not medical advice and not a substitute for a qualified healthcare professional. Stop any exercise that causes sharp or worsening pain, numbness, tingling, dizziness, or chest pain, and seek medical care. If you have an injury or a medical condition, check with a professional before starting."

    /// Red-flag symptoms that warrant professional / urgent care.
    static let redFlags = "sharp or severe pain, pain after a fall or injury, numbness or tingling, weakness, dizziness, or chest pain"
}

// MARK: - Caution card (per-exercise)

struct CautionCard: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LuminaIconBadge(systemName: "exclamationmark.triangle.fill", tint: .pastelPeach, size: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Caution")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.pastelPeach)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.luminaCardFill, in: RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
                .strokeBorder(Color.pastelPeach.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Caution. \(text)")
    }
}

// MARK: - Animation accuracy note (per-exercise)

/// Small disclaimer for exercises whose generated 3D animation is a known
/// approximation — e.g. the rig has no bone for the joint that actually
/// does the moving (no wrist/hand/ankle/foot bone). Deliberately as light
/// as `MedicalDisclaimerNote`, not a full `CautionCard` — this isn't a
/// safety warning, just an accuracy caveat.
struct AnimationAccuracyNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("This animation may not be 100% accurate to the exercise.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Note: this animation may not be 100% accurate to the exercise.")
    }
}

// MARK: - Global medical disclaimer note

struct MedicalDisclaimerNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "cross.case")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(Safety.disclaimer)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Medical disclaimer. \(Safety.disclaimer)")
    }
}

// MARK: - Previews

#Preview("Caution card") {
    CautionCard(text: "Skip or ease off if you have acute lower-back pain or sciatica. Move slowly and never force the stretch.")
        .padding()
}

#Preview("Disclaimer") {
    MedicalDisclaimerNote()
        .padding()
}
