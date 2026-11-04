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
                // ── Tab content ───────────────────────────────────────────────
                // The header and segment selector scroll with the list (as
                // the reference's profile card does) instead of being pinned.
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 18) {
                            profileHeader
                            if let profile { saverBanner(profile) }
                            tabBar
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
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
                .labelStyle(LuminaPastelLabelStyle())
                .headerProminence(.increased)
                .listSectionSpacing(22)
                .environment(\.defaultMinListRowHeight, 54)
                .scrollContentBackground(.hidden)
                .background(Color.luminaSurface)
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
            }
            .toolbar(.hidden, for: .navigationBar)
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
        HStack(alignment: .top, spacing: 18) {
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                ZStack(alignment: .topTrailing) {
                    avatarSquare
                        .frame(width: 108, height: 108)

                    // Edit badge: a pastel star-burst-ish circle, as in the
                    // reference's pencil badge.
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.onPastel)
                        .frame(width: 30, height: 30)
                        .background(Color.pastelPink, in: Circle())
                        .overlay(Circle().strokeBorder(Color.luminaSurface, lineWidth: 3))
                        .offset(x: 10, y: -10)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change profile photo")

            VStack(alignment: .leading, spacing: 10) {
                Text(profile?.displayName ?? auth.displayName)
                    .font(.luminaDisplay)
                    .tracking(-0.8)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(Color.luminaOnSurface)

                if let profile {
                    HStack(alignment: .top, spacing: 18) {
                        headerStat(value: "\(profile.streak)", caption: "STREAK")
                        headerStat(value: "\(profile.totalMinutes)", caption: "MINUTES")
                        headerStat(value: "\(profile.totalPoints)", caption: "POINTS")
                    }
                } else if !auth.userEmail.isEmpty {
                    Text(auth.userEmail)
                        .font(.luminaCaption)
                        .foregroundStyle(Color.luminaOnSurfaceVariant)
                }
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Profile: \(profile?.displayName ?? auth.displayName). \(profile?.streak ?? 0) day streak."
        )
    }

    private func headerStat(value: String, caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(.subheadline, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.luminaOnSurface)
            Text(caption)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.luminaOnSurfaceVariant)
        }
    }

    /// The olive pill under the header (the reference's ID/expiry banner),
    /// here carrying real data: streak savers on hand and badges earned.
    private func saverBanner(_ profile: UserProfile) -> some View {
        HStack {
            Label {
                Text("\(profile.streakFreezeTokens) streak savers")
            } icon: {
                Image(systemName: "shield.lefthalf.filled")
            }
            .labelStyle(.titleAndIcon)
            Spacer()
            Text("\(profile.badges.count) badges")
                .monospacedDigit()
        }
        .font(.system(.footnote, weight: .semibold))
        .foregroundStyle(Color.onPastel)
        .padding(.horizontal, 18)
        .frame(height: 42)
        .background(Color.pastelOlive, in: Capsule())
    }

    @ViewBuilder
    private var avatarSquare: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if let img = profileImage {
            img.resizable().scaledToFill().clipShape(shape)
        } else {
            ZStack {
                shape.fill(Color.pastelBlue)
                Text((profile?.displayName ?? auth.displayName).prefix(1).uppercased())
                    .font(.custom("ManropeExtraLight-ExtraBold", size: 48, relativeTo: .largeTitle))
                    .foregroundStyle(Color.onPastel)
            }
        }
    }

    // MARK: - 3-segment selector
    //
    // Ink capsule on a beige track — icon + label, like a segmented control.

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                let isOn = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: tabBarIconSize * 0.8, weight: .semibold))
                        Text(LocalizedStringKey(tab.rawValue))
                            .font(.system(size: tabBarLabelSize + 2, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .foregroundStyle(isOn ? Color.luminaOnPrimary : Color.luminaOnSurfaceVariant)
                    .background(isOn ? Color.luminaPrimary : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.luminaCardFill, in: Capsule())
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
