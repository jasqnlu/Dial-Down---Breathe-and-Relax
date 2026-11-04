import SwiftUI

struct EmailAuthView: View {
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var isSignUp   = true
    @State private var email      = ""
    @State private var password   = ""
    @State private var confirmPwd = ""
    @State private var errorMsg: String?
    @State private var isLoading  = false

    private let notifyFeedback = UINotificationFeedbackGenerator()
    private let impactFeedback  = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // Header
                    VStack(spacing: 6) {
                        LuminaIconBadge(systemName: "envelope.fill", tint: .pastelBlue, size: 64)
                        Text(isSignUp ? "Create Account" : "Welcome Back")
                            .font(.luminaTitle)
                            .foregroundStyle(Color.luminaOnSurface)
                        Text(isSignUp ? "Sign up with your email address." : "Sign in to your account.")
                            .font(.luminaSubheadline)
                            .foregroundStyle(Color.luminaOnSurfaceVariant)
                    }
                    .padding(.top, 8)

                    // Fields
                    VStack(spacing: 14) {
                        AuthField(label: "Email", text: $email,
                                  icon: "envelope", contentType: .emailAddress,
                                  keyboard: .emailAddress)

                        // Password field + always-present strength bar
                        // (opacity-based so the SecureField never loses identity)
                        VStack(spacing: 8) {
                            AuthField(label: "Password", text: $password,
                                      icon: "lock",
                                      contentType: isSignUp ? .newPassword : .password,
                                      isSecure: true)

                            if isSignUp {
                                PasswordStrengthBar(password: password)
                                    .opacity(password.isEmpty ? 0 : 1)
                            }
                        }

                        if isSignUp {
                            AuthField(label: "Confirm Password", text: $confirmPwd,
                                      icon: "lock.rotation",
                                      contentType: .newPassword,
                                      isSecure: true)
                        }
                    }

                    // Error
                    if let err = errorMsg {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(err)
                        }
                        .font(.luminaLabel)
                        .foregroundStyle(Color.pastelCoral)
                        .padding(10)
                        .background(Color.pastelCoral.opacity(0.12), in: RoundedRectangle(cornerRadius: LuminaRadius.badge))
                    }

                    // Primary action
                    Button { submit() } label: {
                        Group {
                            if isLoading {
                                ProgressView().tint(Color.luminaOnPrimary)
                            } else {
                                Text(isSignUp ? "Create Account" : "Sign In")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LuminaPillButtonStyle())
                    .disabled(isLoading)

                    // Toggle sign in / sign up
                    Button {
                        impactFeedback.impactOccurred()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSignUp.toggle()
                            errorMsg = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                                .foregroundStyle(Color.luminaOnSurfaceVariant)
                            Text(isSignUp ? "Sign In" : "Sign Up")
                                .foregroundStyle(Color.luminaPrimary)
                        }
                        .font(.luminaLabel)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(Color.luminaSurface.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Submit

    private func submit() {
        errorMsg = nil
        isLoading = true
        notifyFeedback.prepare()
        Task {
            if isSignUp {
                guard password == confirmPwd else {
                    errorMsg = "Passwords do not match."
                    notifyFeedback.notificationOccurred(.error)
                    isLoading = false
                    return
                }
                if let err = await auth.signUp(email: email, password: password) {
                    errorMsg = err
                    notifyFeedback.notificationOccurred(.error)
                } else {
                    notifyFeedback.notificationOccurred(.success)
                    dismiss()
                }
            } else {
                if let err = await auth.signIn(email: email, password: password) {
                    errorMsg = err
                    notifyFeedback.notificationOccurred(.error)
                } else {
                    notifyFeedback.notificationOccurred(.success)
                    dismiss()
                }
            }
            isLoading = false
        }
    }
}

// MARK: - Password strength bar

private struct PasswordStrengthBar: View {
    let password: String

    private var score: Int {
        var s = 0
        if password.count >= 8  { s += 1 }
        if password.count >= 12 { s += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { s += 1 }
        let symbols = CharacterSet.letters.union(.decimalDigits).inverted
        if password.rangeOfCharacter(from: symbols) != nil { s += 1 }
        return s
    }

    private var label: String {
        switch score {
        case 0, 1: return "Weak"
        case 2:    return "Fair"
        case 3:    return "Good"
        default:   return "Strong"
        }
    }

    private var color: Color {
        switch score {
        case 0, 1: return .pastelCoral
        case 2:    return .pastelPeach
        case 3:    return .pastelYellow
        default:   return .pastelMint
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(1...4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(i <= score ? color : Color.luminaContainer)
                        .frame(height: 4)
                        .animation(.easeInOut(duration: 0.25), value: score)
                }
            }
            HStack(spacing: 0) {
                Text("Password strength: ")
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
                Text(label)
                    .foregroundStyle(color)
                    .fontWeight(.semibold)
            }
            .font(.luminaCaption)
            .animation(.easeInOut(duration: 0.2), value: label)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Reusable field

private struct AuthField: View {
    let label: String
    @Binding var text: String
    let icon: String
    var contentType: UITextContentType? = nil
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.luminaOnSurfaceVariant)
                .frame(width: 20)

            if isSecure {
                SecureField(label, text: $text)
                    .textContentType(contentType)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
            } else {
                TextField(label, text: $text)
                    .textContentType(contentType)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .font(.luminaBody)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.luminaContainer,
                    in: RoundedRectangle(cornerRadius: LuminaRadius.tag))
    }
}

#Preview {
    EmailAuthView()
        .environmentObject(AuthManager.shared)
}
