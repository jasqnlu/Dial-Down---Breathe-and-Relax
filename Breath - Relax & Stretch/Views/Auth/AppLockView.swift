import SwiftUI
import LocalAuthentication

// MARK: - AppLockView
// Biometric gate shown on cold launch when App Lock is enabled. This is a
// local privacy screen (Face ID / Touch ID / passcode) — deliberately NOT
// branded as "two-factor authentication", because there is no second factor:
// it locks the app, it doesn't verify an account.

struct AppLockView: View {
    @EnvironmentObject private var auth: AuthManager
    @State private var failed = false
    @State private var isAuthenticating = false

    private var biometricLabel: String {
        let ctx = LAContext()
        var err: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) {
            return ctx.biometryType == .faceID ? "Face ID" : "Touch ID"
        }
        return "Passcode"
    }

    private var biometricIcon: String {
        let ctx = LAContext()
        var err: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) {
            return ctx.biometryType == .faceID ? "faceid" : "touchid"
        }
        return "lock.fill"
    }

    var body: some View {
        ZStack {
            Color.luminaSurface.ignoresSafeArea()

            VStack(spacing: 36) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.luminaCardFill)
                        .overlay(Circle().strokeBorder(Color.luminaHairline, lineWidth: 0.5))
                        .frame(width: 132, height: 132)
                    Image(systemName: biometricIcon)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(Color.onPastel)
                        .frame(width: 88, height: 88)
                        .background(Color.pastelLavender, in: Circle())
                }

                // Text
                VStack(spacing: 10) {
                    Text("App Locked")
                        .font(.luminaHeadline)
                        .foregroundStyle(Color.luminaOnSurface)
                    Text("Use \(biometricLabel) to unlock the app.")
                        .font(.luminaSubheadline)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                if failed {
                    Text("Couldn't unlock. Try again.")
                        .font(.luminaLabel)
                        .foregroundStyle(Color.pastelCoral)
                }

                // Unlock button
                Button {
                    unlock()
                } label: {
                    HStack(spacing: 8) {
                        if isAuthenticating {
                            ProgressView().tint(Color.luminaOnPrimary)
                        } else {
                            Image(systemName: biometricIcon)
                            Text("Unlock with \(biometricLabel)")
                        }
                    }
                    .font(.luminaCardTitle)
                    .foregroundStyle(Color.luminaOnPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.luminaPrimary, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .disabled(isAuthenticating)

                // Sign out escape hatch
                Button("Sign out instead") {
                    auth.signOut()
                }
                .font(.luminaLabel)
                .foregroundStyle(Color.luminaOnSurfaceVariant)

                Spacer()
            }
        }
        .onAppear { unlock() }
    }

    private func unlock() {
        isAuthenticating = true
        failed = false
        Task {
            let ok = await auth.authenticateWithBiometrics()
            await MainActor.run {
                isAuthenticating = false
                if ok {
                    auth.completeUnlock()
                } else {
                    failed = true
                }
            }
        }
    }
}

#Preview {
    AppLockView()
        .environmentObject(AuthManager.shared)
}
