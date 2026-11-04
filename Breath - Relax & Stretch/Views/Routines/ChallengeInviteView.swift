import SwiftUI

// MARK: - ChallengeInviteView
// Shown when the app is opened via a shared `breath://challenge` link.

struct ChallengeInviteView: View {
    let payload: ChallengePayload
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 0)

                LuminaIconBadge(systemName: "flame.fill", tint: .pastelYellow, size: 96)

                Text("\(payload.fromName.isEmpty ? "A friend" : payload.fromName) challenges you!")
                    .font(.luminaTitle)
                    .foregroundStyle(Color.luminaOnSurface)
                    .multilineTextAlignment(.center)

                Text("They're on a \(payload.streak)-day streak with \(payload.totalPoints) points. Think you can keep up?")
                    .font(.luminaSubheadline)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer(minLength: 0)

                Button(action: onAccept) {
                    Text("Accept & Start a Session")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LuminaPillButtonStyle())
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color.luminaSurface.ignoresSafeArea())
            .navigationTitle("Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss", action: onDismiss)
                }
            }
        }
    }
}

#Preview {
    ChallengeInviteView(
        payload: ChallengePayload(fromName: "Jason", streak: 12, totalPoints: 840),
        onAccept: {}, onDismiss: {}
    )
}
