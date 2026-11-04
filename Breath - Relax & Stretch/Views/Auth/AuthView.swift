import SwiftUI
import AuthenticationServices

// MARK: - AuthView
// Guest-first welcome screen. The primary action starts using the app with no
// account (continueAsGuest); Apple / Google / Email sign-in are offered as the
// quieter secondary path for people who want their name on their profile.

struct AuthView: View {
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var showEmailAuth = false
    /// Single error slot shared by both providers, so a new sign-in attempt
    /// always replaces whatever error (if any) the other provider left behind
    /// instead of the Apple/Google errors silently going stale next to each other.
    @State private var authError: String?
    @State private var isBreathingIn = false
    @State private var legalDocument: LegalDocument?

    var body: some View {
        ZStack {
            // Modern black (seperate-main): plain surface, no gradient.
            Color.luminaSurface.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // MARK: Hero — the mark in a softly breathing pastel halo
                VStack(spacing: 18) {
                    breathingHalo

                    Text("Dial Down")
                        .font(.luminaDisplay)
                        .foregroundStyle(Color.luminaOnSurface)

                    Text("Relax. Stretch. Breathe.")
                        .font(.luminaSubheadline)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)

                    featureRow
                        .padding(.top, 6)
                }

                Spacer()

                VStack(spacing: 14) {
                    // MARK: Primary — use the app right now, no account.
                    // Hidden when a guest re-opens this screen to add an
                    // account (they're already "in").
                    if !auth.isGuest {
                        Button {
                            auth.continueAsGuest()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "wind")
                                Text("Start breathing")
                            }
                            .font(.luminaCardTitle)
                            .foregroundStyle(Color.luminaOnPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.luminaPrimary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Start breathing")

                        // MARK: Divider
                        HStack(spacing: 12) {
                            line
                            Text("or save your progress")
                                .font(.luminaCaption)
                                .foregroundStyle(Color.luminaOnSurfaceVariant)
                                .fixedSize()
                            line
                        }
                        .padding(.vertical, 2)
                    }

                    // MARK: Secondary — account options
                    SignInWithAppleButton(.signIn) { request in
                        // Sets scopes + a nonce so the identity token can be
                        // exchanged with Supabase Auth without replay risk.
                        AuthManager.shared.prepareAppleSignInRequest(request)
                    } onCompletion: { result in
                        switch result {
                        case .success(let auth):
                            authError = nil
                            if let credential = auth.credential as? ASAuthorizationAppleIDCredential {
                                AuthManager.shared.handleAppleCredential(credential)
                            }
                        case .failure(let error):
                            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                                authError = error.localizedDescription
                            }
                        }
                    }
                    // Black button + hairline so it sits one step below the
                    // white primary, like Google/Email beside it.
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 48)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.luminaOutline, lineWidth: 1))

                    HStack(spacing: 12) {
                        secondaryButton(
                            icon: "g.circle.fill",
                            title: GoogleAuthService.isConfigured ? "Google" : "Google (soon)",
                            enabled: GoogleAuthService.isConfigured
                        ) {
                            Task { await signInWithGoogle() }
                        }

                        secondaryButton(icon: "envelope.fill", title: "Email", enabled: true) {
                            showEmailAuth = true
                        }
                    }

                    if let err = authError {
                        Text(err)
                            .font(.luminaCaption)
                            .foregroundStyle(Color.pastelCoral)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)

                // MARK: Legal
                HStack(spacing: 4) {
                    Text("By continuing you agree to our")
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                    Button("Terms of Use") { legalDocument = .termsOfUse }
                        .underline()
                    Text("and")
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                    Button("Privacy Policy") { legalDocument = .privacyPolicy }
                        .underline()
                }
                .font(.luminaCaption)
                .foregroundStyle(Color.luminaOnSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showEmailAuth) {
            EmailAuthView()
                .environmentObject(auth)
        }
        .sheet(item: $legalDocument) { document in
            LegalDocumentView(document: document)
        }
        // When shown as a sheet over a guest session, close once the guest
        // upgrades to a real provider. (At the root this view is swapped out
        // by RootView instead, so dismiss() is a harmless no-op there.)
        .onChange(of: auth.provider) { _, newProvider in
            if newProvider != .guest { dismiss() }
        }
        .onAppear {
            guard !reduceMotion else { return }
            isBreathingIn = true
        }
    }

    // MARK: - Pieces

    /// The Dial Down mark inside two pastel rings that swell and settle at a
    /// calm breath cadence. The animation is scoped via .animation(value:) —
    /// a global withAnimation(.repeatForever) would leak into every
    /// concurrent layout change on screen, forever.
    private var breathingHalo: some View {
        ZStack {
            Circle()
                .fill(Color.pastelLavender.opacity(0.08))
                .frame(width: 170, height: 170)
                .scaleEffect(isBreathingIn ? 1.14 : 0.94)
            Circle()
                .fill(Color.luminaCardFill)
                .overlay(Circle().strokeBorder(Color.pastelBlue.opacity(0.55), lineWidth: 2))
                .frame(width: 128, height: 128)
                .scaleEffect(isBreathingIn ? 1.06 : 0.97)
            DialDownMark(motion: .still)
                .frame(height: 64)
        }
        .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: isBreathingIn)
        .frame(width: 200, height: 200)
        .accessibilityHidden(true)
    }

    /// Three pastel icon circles naming what the app does.
    private var featureRow: some View {
        HStack(spacing: 18) {
            feature("wind", "Breathe", .pastelBlue)
            feature("figure.flexibility", "Stretch", .pastelMint)
            feature("flame.fill", "Streaks", .pastelYellow)
        }
    }

    private func feature(_ icon: String, _ title: String, _ tint: Color) -> some View {
        VStack(spacing: 6) {
            LuminaIconBadge(systemName: icon, tint: tint, size: 40)
            Text(title)
                .font(.luminaCaption.weight(.semibold))
                .foregroundStyle(Color.luminaOnSurfaceVariant)
        }
    }

    private var line: some View {
        Rectangle()
            .fill(Color.luminaOutline)
            .frame(height: 1)
    }

    private func secondaryButton(icon: String, title: String, enabled: Bool,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                Text(title)
                    .font(.luminaCardTitle)
            }
            .foregroundStyle(Color.luminaOnSurface.opacity(enabled ? 1 : 0.45))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.luminaCardFill, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.luminaOutline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func signInWithGoogle() async {
        guard let anchor = ASPresentationAnchor.currentWindow else { return }
        do {
            let result = try await GoogleAuthService.shared.signIn(presentationAnchor: anchor)
            authError = await auth.handleGoogleSignIn(
                idToken: result.idToken, nonce: result.nonce,
                name: result.user.name, email: result.user.email
            )
        } catch GoogleAuthService.GoogleAuthError.cancelled {
            // User dismissed the sheet — not an error worth surfacing.
        } catch {
            authError = error.localizedDescription
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthManager.shared)
}
