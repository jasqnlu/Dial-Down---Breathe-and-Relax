import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Profile tab selector

private enum ProfileTab: String, CaseIterable {
    case account    = "Account"
    case settings   = "Settings"
    case appearance = "Appearance"

    var icon: String {
        switch self {
        case .account:    return "person.circle"
        case .settings:   return "gearshape"
        case .appearance: return "paintpalette"
        }
    }
}

// MARK: - ProfileView

struct ProfileView: View {
    @Query private var profiles: [UserProfile]
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var tourCoordinator: TourCoordinator

    // SceneStorage (not @State): a language change rebuilds this tab, and the
    // user should land back on the segment they were on (usually Settings).
    @SceneStorage("profileSelectedTab") private var selectedTab: ProfileTab = .account
    @State private var showSignOutConfirm = false
    @State private var confirmingSaverPurchase = false
    @Environment(\.modelContext) private var modelContext

    // Profile photo
    @State private var profileImage: Image?
    @State private var photoPickerItem: PhotosPickerItem?

    // Header display
    @AppStorage("accentColorName")  private var accentColorName = "Blue"
    @AppStorage("showStreakEmoji") private var showStreakEmoji = true

    // Icon/label pair in the 3-segment tab bar below, kept in proportion the
    // same way CustomTabBar does.
    @ScaledMetric(relativeTo: .caption) private var tabBarIconSize: CGFloat = 18
    @ScaledMetric(relativeTo: .caption) private var tabBarLabelSize: CGFloat = 11

    private let accentOptions: [(name: String, color: Color)] = [
        ("Blue", .blue), ("Purple", .purple), ("Pink", .pink),
        ("Red",  .red),  ("Orange", .orange), ("Green", .green),
    ]

    var profile: UserProfile? { profiles.first }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ── Profile header ────────────────────────────────────────────
                profileHeader
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color.luminaSurface)

                Divider()

                // ── 3-segment tab bar ─────────────────────────────────────────
                tabBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.luminaSurface)

                Divider()

                // ── Tab content ───────────────────────────────────────────────
                List {
                    switch selectedTab {
                    case .account:
                        ProfileAccountTab(profile: profile,
                                          showSignOutConfirm: $showSignOutConfirm)
                    case .settings:
                        ProfileSettingsTab(confirmingSaverPurchase: $confirmingSaverPurchase)
                    case .appearance:
                        ProfileAppearanceTab()
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.luminaSurface)
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .floatingTabBarClearance()
            .onAppear { profileImage = loadProfilePhoto() }
            .onChange(of: tourCoordinator.currentStep?.id) { _, stepID in
                switch stepID {
                case "profile.stats":       selectedTab = .account
                case "profile.restartTour": selectedTab = .settings
                default: break
                }
            }
            .onChange(of: photoPickerItem) { _, item in
                Task {
                    guard let item else { return }
                    do {
                        if let data = try await item.loadTransferable(type: Data.self) {
                            saveProfilePhoto(data)
                            if let uiImage = UIImage(data: data) {
                                profileImage = Image(uiImage: uiImage)
                            }
                        }
                    } catch { /* ignore photo loading errors */ }
                }
            }
            .confirmationDialog("Sign out of your account?",
                                isPresented: $showSignOutConfirm,
                                titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { auth.signOut() }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(
                "Spend \(GamificationService.saverCost) points on a streak saver?",
                isPresented: $confirmingSaverPurchase,
                titleVisibility: .visible
            ) {
                Button("Buy Saver") {
                    if let profile, GamificationService.buySaver(for: profile) {
                        try? modelContext.save()
                        ProfileSyncService.upload(profile)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        HStack(spacing: 16) {
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    avatarCircle
                        .frame(width: 64, height: 64)

                    // Camera badge
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(accentColor, in: Circle())
                        .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change profile photo")

            VStack(alignment: .leading, spacing: 3) {
                Text(profile?.displayName ?? auth.displayName)
                    .font(.luminaTitle)
                if !auth.userEmail.isEmpty {
                    Text(auth.userEmail)
                        .font(.luminaCaption)
                        .foregroundStyle(.secondary)
                }
                if let profile {
                    HStack(spacing: 4) {
                        if showStreakEmoji { Text("🔥") }
                        Text("\(profile.streak) day streak · \(profile.totalPoints) pts")
                            .font(.luminaCaption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Profile: \(profile?.displayName ?? auth.displayName). \(profile?.streak ?? 0) day streak."
        )
    }

    @ViewBuilder
    private var avatarCircle: some View {
        if let img = profileImage {
            img.resizable().scaledToFill().clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(accentColor.opacity(0.15))
                Text((profile?.displayName ?? auth.displayName).prefix(1).uppercased())
                    .font(.title.bold())
                    .foregroundStyle(accentColor)
            }
        }
    }

    // MARK: - 3-segment tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: tabBarIconSize,
                                          weight: selectedTab == tab ? .semibold : .regular))
                        Text(tab.rawValue)
                            .font(.system(size: tabBarLabelSize,
                                          weight: selectedTab == tab ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(selectedTab == tab ? Color.luminaPrimary : Color.luminaOnSurfaceVariant)
                    .background(
                        RoundedRectangle(cornerRadius: LuminaRadius.chip)
                            .fill(selectedTab == tab ? Color.luminaCardFill : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.luminaContainer, in: RoundedRectangle(cornerRadius: LuminaRadius.panel))
    }

    // MARK: - Profile photo helpers

    private var profilePhotoURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_photo.jpg")
    }

    private func saveProfilePhoto(_ data: Data) {
        guard let uiImage = UIImage(data: data) else { return }
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            uiImage.draw(in: CGRect(origin: .zero, size: size))
        }
        let jpeg = resized.jpegData(compressionQuality: 0.85) ?? data
        try? jpeg.write(to: profilePhotoURL, options: .atomic)
    }

    private func loadProfilePhoto() -> Image? {
        guard let data = try? Data(contentsOf: profilePhotoURL),
              let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
    }

    // MARK: - Accent color

    private var accentColor: Color {
        accentOptions.first { $0.name == accentColorName }?.color ?? .accentColor
    }
}

// MARK: - Preview

#Preview {
    ProfileView()
        .modelContainer(for: UserProfile.self, inMemory: true)
        .environmentObject(AuthManager.shared)
}
