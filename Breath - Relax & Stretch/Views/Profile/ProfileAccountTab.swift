import SwiftUI
import SwiftData

// MARK: - Account Tab

struct ProfileAccountTab: View {
    let profile: UserProfile?
    @EnvironmentObject private var auth: AuthManager
    @Binding var showSignOutConfirm: Bool
    @State private var appLockOn = false
    @State private var showingSignIn = false
    @State private var showDeleteConfirm = false

    var body: some View {
        Group {
            // Stats
            if let profile {
                Section("Your Stats") {
                    statsRow(icon: "clock.fill",  color: .blue,
                             label: "Total Minutes", value: "\(profile.totalMinutes) min")
                    statsRow(icon: "star.fill",   color: .yellow,
                             label: "Total Points",  value: "\(profile.totalPoints) pts")
                    statsRow(icon: "flame.fill",  color: .orange,
                             label: "Current Streak", value: String(localized: "\(profile.streak) days"))
                    statsRow(icon: "medal.fill",  color: .purple,
                             label: "Badges Earned", value: "\(profile.badges.count)")
                }
                .tourAnchor("profile.stats")

                Section {
                    NavigationLink(destination: BadgesView(earnedBadges: profile.badges)) {
                        Label("View All Badges", systemImage: "medal")
                    }
                    NavigationLink(destination: ProgressChartsView()) {
                        Label("Progress & Charts", systemImage: "chart.bar.xaxis")
                    }
                }

                Section("Community") {
                    // The leaderboard needs the backend; keep the entry point
                    // hidden rather than showing a screen that can't load.
                    if SupabaseService.isConfigured {
                        NavigationLink(destination: LeaderboardView()) {
                            Label("Leaderboard", systemImage: "list.number")
                        }
                    }
                    if let url = challengeURL(for: profile) {
                        ShareLink(item: url) {
                            Label("Challenge a Friend", systemImage: "figure.2")
                        }
                    }
                }
            }

            // Security
            Section {
                Toggle(isOn: $appLockOn) {
                    Label("App Lock", systemImage: "faceid")
                }
                .onChange(of: appLockOn) { _, val in auth.appLockEnabled = val }
            } header: {
                Text("Security")
                    .font(.luminaLabel)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
            } footer: {
                Text("Require Face ID, Touch ID, or your passcode to open the app.")
            }

            // Account
            Section("Account") {
                if auth.isGuest {
                    Button {
                        showingSignIn = true
                    } label: {
                        Label("Sign In or Create Account", systemImage: "person.crop.circle.badge.plus")
                    }
                } else {
                    LabeledContent("Signed in with") {
                        Text(auth.provider.rawValue.capitalized).foregroundStyle(.secondary)
                    }
                }

                if auth.isSignedIn {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                if auth.isSignedIn && !auth.isGuest {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Account", systemImage: "trash")
                    }
                }
            }
        }
        .listRowBackground(Color.luminaCardFill)
        .onAppear { appLockOn = auth.appLockEnabled }
        .sheet(isPresented: $showingSignIn) {
            AuthView()
                .environmentObject(auth)
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) { Task { try? await auth.deleteAccount(appleReauth: nil) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes your sign-in credentials from this device. Your session history stays on this device and can be cleared separately in Settings.")
        }
    }

    // MARK: Helpers

    private func challengeURL(for profile: UserProfile) -> URL? {
        ChallengePayload(fromName: profile.displayName, streak: profile.streak, totalPoints: profile.totalPoints).shareURL
    }

    private func statsRow(icon: String, color: Color,
                          label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color).frame(width: 28)
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).fontWeight(.medium)
        }
    }
}
