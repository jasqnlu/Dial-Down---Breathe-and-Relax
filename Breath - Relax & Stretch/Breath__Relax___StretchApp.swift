import SwiftUI
import SwiftData
import os

@main
struct BreathRelaxStretchApp: App {
    @StateObject private var auth = AuthManager.shared
    @StateObject private var deepLinkRouter = DeepLinkRouter()
    @StateObject private var pickingSession = ExercisePickingSession()
    @StateObject private var tourCoordinator = TourCoordinator()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Set (once, before any UI appears) when `sharedModelContainer` had to
    /// fall back to an in-memory store below. Read from `body`'s `.onAppear`
    /// to surface `showDataNotSavingAlert` instead of failing silently — the
    /// fallback itself is still the right behavior (keeps the app launching)
    /// but the user deserves to know this session's data won't persist.
    private static var didFallBackToInMemoryStore = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Exercise.self,
            FlexibilityCheckIn.self,
            PendingSyncOp.self,
            Routine.self,
            Session.self,
            UserProfile.self,
        ])
        // Local-only storage. iCloud sync requires the iCloud + CloudKit
        // capabilities (not yet added to the project) — with .automatic and no
        // entitlement the store can fail to open and silently dump users into
        // the in-memory fallback below. Flip to .automatic only alongside the
        // entitlement and visible error UI.
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // iCloud schema conflicts after an upgrade can make the persistent store
            // fail to open. Fall back to an in-memory container so the app at least
            // launches; the user will lose synced data for this session but can
            // reopen to get a fresh persistent store on the next cold start.
            Logger(subsystem: "com.jasonlu.breath", category: "modelContainer").warning("Failed to open persistent store, falling back to in-memory: \(error)")
            didFallBackToInMemoryStore = true
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return (try? ModelContainer(for: schema, configurations: [fallback]))
                ?? { fatalError("Could not create any ModelContainer: \(error)") }()
        }
    }()

    // The app is dark-only (Liquid Glass redesign, 2026-09-05) — there is no
    // user-facing light mode or system-follow option anymore. This used to
    // read a Profile > Appearance picker; that picker is gone (see
    // ProfileAppearanceTab.swift), so this always resolves to dark.
    private var resolvedColorScheme: ColorScheme? { .dark }

    /// Gates the splash (`AppLoadingView`) until the anatomy mesh is warm and
    /// a minimum readable duration has elapsed. See `minimumSplashDuration`.
    @State private var isPreloading = true
    private static let minimumSplashDuration: UInt64 = 1_500_000_000 // 1.5s, in nanoseconds

    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.system.rawValue
    @AppStorage("seedDataVersion") private var seedDataVersion: Int = 0
    /// Highest seed version that added new exercises the user should be told
    /// about. Later data-only migrations bump `seedDataVersion` past this.
    private static let latestContentSeedVersion = 4
    @AppStorage("notifiedSeedVersion") private var notifiedSeedVersion: Int = 0
    @State private var showNewContentAlert = false
    @State private var showDataNotSavingAlert = false

    init() {
        LuminaFonts.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isPreloading {
                    AppLoadingView()
                        .transition(.opacity)
                } else {
                    OnboardingGate {
                        RootView()
                    }
                    .preferredColorScheme(resolvedColorScheme)
                    .environmentObject(auth)
                    .environmentObject(deepLinkRouter)
                    .environmentObject(pickingSession)
                    .environmentObject(tourCoordinator)
                    .onAppear {
                        let freshInstall = seedIfNeeded()
                        migrateSeedIfNeeded()
                        claimOwnerlessRoutines()
                        if freshInstall {
                            // A first-ever launch already has all the content — don't
                            // greet new users with a "New Content Added" alert.
                            notifiedSeedVersion = seedDataVersion
                        } else if notifiedSeedVersion < Self.latestContentSeedVersion {
                            // Only greet users about versions that actually added new
                            // exercises. Data-only migrations (e.g. v5's isBilateral
                            // flag) bump seedDataVersion but shouldn't pop the alert.
                            showNewContentAlert = true
                        }
                        if Self.didFallBackToInMemoryStore {
                            showDataNotSavingAlert = true
                        }
                    }
                    .alert("New Content Added", isPresented: $showNewContentAlert) {
                        Button("Got it") { notifiedSeedVersion = seedDataVersion }
                    } message: {
                        Text("New stretches were added covering every muscle group — find them in the Exercises tab.")
                    }
                    .alert("Changes Won't Be Saved", isPresented: $showDataNotSavingAlert) {
                        Button("OK") {}
                    } message: {
                        Text("Your saved data couldn't be opened, so this session is running in a temporary mode — anything you do now will be lost when you close the app. Reopening the app again may restore normal saving.")
                    }
                    .task {
                        await syncRemoteCatalog()
                        if shouldRegisterForRemotePush() {
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    }
                }
            }
            // In-app language override (onboarding's first page / Settings).
            // Applied above the splash/onboarding split so every screen, alert
            // and sheet resolves its strings in the chosen language live.
            .environment(\.locale, AppLanguage(stored: appLanguage).locale ?? .autoupdatingCurrent)
            // Mounted unconditionally (not inside the `else` branch above) so a
            // cold-launch deep link — a widget tap, a shared routine/challenge
            // link — is still caught during the splash window, not only once
            // `isPreloading` flips false. `DeepLinkRouter.pendingAction` already
            // queues until a consumer (HomeView) is ready, exactly as it does
            // today for the auth/onboarding gate, so routing through it here
            // needs no new queuing logic.
            .onOpenURL { url in
                deepLinkRouter.handle(url)
            }
            .task {
                guard isPreloading else { return }
                async let meshWarm: Void = warmBodyMesh()
                async let minimumDelay: Void = pauseForReadability()
                await meshWarm
                await minimumDelay
                withAnimation(.easeInOut(duration: 0.3)) {
                    isPreloading = false
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: - Launch preload

    /// Warms `BodyMeshLoader`'s in-memory cache so the first `BodySceneView`
    /// the user opens never has to parse the 12MB anatomy OBJ itself. Result
    /// is discarded — a parse failure just means `BodySceneView` falls back
    /// to its existing "3D Model Unavailable" state later, on demand.
    private func warmBodyMesh() async {
        _ = await BodyMeshLoader.shared.anatomyParts()
    }

    /// Keeps the splash up for at least `minimumSplashDuration` even when the
    /// mesh preloads faster than that, so the trivia fact is readable.
    private func pauseForReadability() async {
        try? await Task.sleep(nanoseconds: Self.minimumSplashDuration)
    }

    // MARK: - Seed exercises

    /// Returns true when this was a fresh install (no exercises existed yet).
    @discardableResult
    private func seedIfNeeded() -> Bool {
        let context = sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Exercise>()
        guard (try? context.fetchCount(descriptor)) == 0 else { return false }

        guard
            let url  = Bundle.main.url(forResource: "SeedData", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let exercises = json["exercises"] as? [[String: Any]]
        else { return true } // still a fresh install, even if the seed failed to load

        for raw in exercises {
            guard
                let name         = raw["name"] as? String,
                let typeStr      = raw["type"] as? String,
                let type         = ExerciseType(rawValue: typeStr.capitalized),
                let parts        = raw["targetBodyParts"] as? [String],
                let duration     = raw["durationSeconds"] as? Int,
                let difficulty   = raw["difficulty"] as? Int,
                let instructions = raw["instructions"] as? [String]
            else { continue }

            let mediaURL = raw["mediaURL"] as? String
            let caution  = raw["caution"] as? String
            // Missing key defaults to true — most stretches are bilateral;
            // the seed only marks the one-side-at-a-time exercises false.
            let isBilateral = raw["isBilateral"] as? Bool ?? true
            // Missing/unparseable key defaults to .hold via Exercise's own
            // inline default — every seed entry has a real value (Task 2),
            // this only guards a malformed bundle.
            let cueStyle = (raw["cueStyle"] as? String).flatMap { ExerciseCueStyle(rawValue: $0.capitalized) } ?? .hold
            let seedID = raw["id"] as? String
            // The seed catalog's own "id" is a permanent UUID independent of
            // `name` — use it directly as the row's identity so two installs
            // seeded at different points in the catalog's naming history (one
            // before an exercise is renamed in SeedData.json, one after) still
            // agree on its uuid. Session.exerciseIDs, Routine.exerciseIDs, and
            // Supabase's RemoteExercise.id all compare these across devices,
            // so a name-derived uuid would silently desync them for any
            // renamed exercise. Falls back to the old name-hash only if the
            // seed entry is somehow missing/malformed a valid id.
            let exercise = Exercise(
                uuid: seedID.flatMap(UUID.init) ?? Exercise.stableSeedUUID(forName: name),
                name: name, type: type, targetBodyParts: parts,
                durationSeconds: duration, difficulty: difficulty,
                instructions: instructions, mediaURL: mediaURL, caution: caution,
                isBilateral: isBilateral, cueStyle: cueStyle
            )
            exercise.seedID = seedID
            exercise.localVideoName = raw["localVideoName"] as? String
            exercise.animationIsApproximate = raw["animationIsApproximate"] as? Bool ?? false
            exercise.animationCallout = AnimationCallout.parse(fromRawExercise: raw)
            if let posesRaw = raw["poses"],
               let posesData = try? JSONSerialization.data(withJSONObject: posesRaw) {
                exercise.posesData = posesData
            }
            if let breathPatternRaw = raw["breathPattern"],
               let breathPatternData = try? JSONSerialization.data(withJSONObject: breathPatternRaw) {
                exercise.breathPatternData = breathPatternData
            }
            context.insert(exercise)
        }
        do {
            try context.save()
        } catch {
            Logger(subsystem: "com.jasonlu.breath", category: "seedData").warning("Seed save failed: \(error)")
        }
        return true
    }

    // MARK: - Seed migration
    // Actual matching/migration logic lives in `SeedMigrator` (testable
    // against an in-memory ModelContext); these are thin wrappers that load
    // the bundle JSON, delegate, and advance `seedDataVersion`. See
    // `SeedMigrator` for the version history and the rename-safety rationale.

    private func migrateSeedIfNeeded() {
        migrateSeedToV3IfNeeded()
        migrateSeedToV4IfNeeded()
        migrateSeedToV5IfNeeded()
        migrateSeedToV6IfNeeded()
        migrateSeedToV7IfNeeded()
        migrateSeedToV8IfNeeded()
        migrateSeedToV9IfNeeded()
        migrateSeedToV10IfNeeded()
        migrateSeedToV11IfNeeded()
        migrateSeedToV12IfNeeded()
        removeRetiredBodyMapStorage()
    }

    /// Loads the bundled seed JSON's exercise array, or nil if unavailable.
    private func loadSeedExercises() -> [[String: Any]]? {
        guard
            let url  = Bundle.main.url(forResource: "SeedData", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawExercises = json["exercises"] as? [[String: Any]]
        else { return nil }
        return rawExercises
    }

    private func migrateSeedToV3IfNeeded() {
        guard seedDataVersion < 3 else { return }
        if let rawExercises = loadSeedExercises() {
            let context = sharedModelContainer.mainContext
            if SeedMigrator.migrateV3(context: context, rawExercises: rawExercises) {
                try? context.save()
            }
        }
        seedDataVersion = 3
    }

    private func migrateSeedToV4IfNeeded() {
        guard seedDataVersion < 4 else { return }
        if let rawExercises = loadSeedExercises() {
            let context = sharedModelContainer.mainContext
            if SeedMigrator.migrateV4(context: context, rawExercises: rawExercises) {
                try? context.save()
            }
        }
        seedDataVersion = 4
    }

    private func migrateSeedToV5IfNeeded() {
        guard seedDataVersion < 5 else { return }
        if let rawExercises = loadSeedExercises() {
            let context = sharedModelContainer.mainContext
            if SeedMigrator.migrateV5(context: context, rawExercises: rawExercises) {
                try? context.save()
            }
        }
        seedDataVersion = 5
    }

    private func migrateSeedToV6IfNeeded() {
        guard seedDataVersion < 6 else { return }
        if let rawExercises = loadSeedExercises() {
            let context = sharedModelContainer.mainContext
            if SeedMigrator.migrateV6(context: context, rawExercises: rawExercises) {
                try? context.save()
            }
        }
        seedDataVersion = 6
    }

    /// Unlike the other steps here, this one is NOT gated behind a one-time
    /// version bump: new animated exercises get added to `SeedData.json` on an
    /// ongoing basis (4 so far, 148 to go), each needing `animationName`
    /// backfilled onto rows that were already seeded before that entry
    /// existed. Gating this behind `seedDataVersion < 7` meant it only ever
    /// ran once, on whichever launch first crossed v7 — any animation added
    /// after a device passed that point would never backfill onto its
    /// already-seeded row. `SeedMigrator.migrateV7` is naturally idempotent
    /// (matches by seedID, only fills an empty `animationName`, no-ops
    /// otherwise), so it's cheap and safe to just run on every launch.
    private func migrateSeedToV7IfNeeded() {
        if let rawExercises = loadSeedExercises() {
            let context = sharedModelContainer.mainContext
            if SeedMigrator.migrateV7(context: context, rawExercises: rawExercises) {
                try? context.save()
            }
        }
        seedDataVersion = max(seedDataVersion, 7)
    }

    private func migrateSeedToV8IfNeeded() {
        guard seedDataVersion < 8 else { return }
        if let rawExercises = loadSeedExercises() {
            let context = sharedModelContainer.mainContext
            if SeedMigrator.migrateV8(context: context, rawExercises: rawExercises) {
                try? context.save()
            }
        }
        seedDataVersion = 8
    }

    /// Like `migrateSeedToV7IfNeeded`, NOT gated behind a one-time version
    /// bump: new exercises get added to `SeedData.json` on an ongoing basis,
    /// and each one needs inserting into every already-seeded install.
    /// `SeedMigrator.migrateV9` is idempotent (matches by seedID, only
    /// inserts rows that aren't already present), so it's cheap and safe to
    /// run on every launch.
    private func migrateSeedToV9IfNeeded() {
        if let rawExercises = loadSeedExercises() {
            let context = sharedModelContainer.mainContext
            if SeedMigrator.migrateV9(context: context, rawExercises: rawExercises) {
                try? context.save()
            }
        }
        seedDataVersion = max(seedDataVersion, 9)
    }

    /// Like `migrateSeedToV9IfNeeded`, NOT gated behind a one-time version
    /// bump: which exercises get flagged `animationIsApproximate` can grow
    /// as more rig limitations/animation bugs are found after this ships.
    private func migrateSeedToV10IfNeeded() {
        if let rawExercises = loadSeedExercises() {
            let context = sharedModelContainer.mainContext
            if SeedMigrator.migrateV10(context: context, rawExercises: rawExercises) {
                try? context.save()
            }
        }
        seedDataVersion = max(seedDataVersion, 10)
    }

    /// Like `migrateSeedToV9IfNeeded`, NOT gated behind a one-time version
    /// bump (this was the original design, and it was wrong): breath
    /// patterns are not a fixed, one-time set — new pattern-bearing
    /// exercises keep getting added to `SeedData.json` in later content
    /// batches, each needing its `breathPattern` backfilled the same way a
    /// brand-new exercise needs inserting by `migrateV9`. A row `migrateV9`
    /// inserts on a later launch never gets `breathPatternData` (that insert
    /// path predates the field), so gating this behind `seedDataVersion < 11`
    /// meant any such row's pattern would never backfill once the device had
    /// already passed v11. `SeedMigrator.migrateV11` is idempotent (matches
    /// by seedID, only fills when the bundle's pattern actually differs), so
    /// it's cheap and safe to run on every launch instead.
    private func migrateSeedToV11IfNeeded() {
        if let rawExercises = loadSeedExercises() {
            let context = sharedModelContainer.mainContext
            if SeedMigrator.migrateV11(context: context, rawExercises: rawExercises) {
                try? context.save()
            }
        }
        seedDataVersion = max(seedDataVersion, 11)
    }

    /// Like `migrateSeedToV10IfNeeded`, NOT gated behind a one-time version
    /// bump: `animationCallout`s are authored incrementally, batch by batch,
    /// so a gated migration would only ever pick up whatever was authored as
    /// of the version-bump launch.
    private func migrateSeedToV12IfNeeded() {
        if let rawExercises = loadSeedExercises() {
            let context = sharedModelContainer.mainContext
            if SeedMigrator.migrateV12(context: context, rawExercises: rawExercises) {
                try? context.save()
            }
        }
        seedDataVersion = max(seedDataVersion, 12)
    }

    /// One-line cleanup of retired body-map marking storage. Unlike the
    /// `migrateSeedToVNIfNeeded` family this has no version gate — it is
    /// idempotent and touches only UserDefaults.
    private func removeRetiredBodyMapStorage() {
        SeedMigrator.removeRetiredBodyMapMarkStorage()
    }

    /// Claims any pre-existing `Routine` rows with no owner (created before
    /// `Routine.ownerID` existed) for whoever is using the device the first
    /// time this runs post-update. See `SeedMigrator.claimOwnerlessRoutines`.
    private func claimOwnerlessRoutines() {
        let context = sharedModelContainer.mainContext
        if SeedMigrator.claimOwnerlessRoutines(context: context, claimant: auth.backendID) {
            try? context.save()
        }
    }

    // MARK: - Remote catalog sync (best-effort, offline-first)

    /// After the bundled seed loads, pull the curated catalog from Supabase and
    /// upsert it into SwiftData. No-ops (silently) when the backend isn't
    /// configured or the device is offline — the seed catalog stays in place.
    @MainActor
    private func syncRemoteCatalog() async {
        guard SupabaseService.isConfigured else { return }
        do {
            let remote = try await SupabaseService.shared.fetchExercises()
            guard !remote.isEmpty else { return }
            upsertExercises(remote, into: sharedModelContainer.mainContext)
        } catch {
            // Offline or backend error — bundled seed remains the source of truth.
        }
    }

    @MainActor
    private func upsertExercises(_ remote: [RemoteExercise], into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var byID: [UUID: Exercise] = [:]
        for ex in existing { byID[ex.uuid] = ex }

        for r in remote {
            guard let id = UUID(uuidString: r.id),
                  let type = ExerciseType(rawValue: r.type.capitalized) else { continue }
            if let ex = byID[id] {
                ex.name            = r.name
                ex.type            = type
                ex.targetBodyParts = r.targetBodyParts
                ex.durationSeconds = r.durationSeconds
                ex.difficulty      = r.difficulty
                ex.instructions    = r.instructions
                ex.mediaURL        = r.mediaURL
                ex.caution         = r.caution
            } else {
                context.insert(Exercise(
                    uuid: id, name: r.name, type: type,
                    targetBodyParts: r.targetBodyParts,
                    durationSeconds: r.durationSeconds, difficulty: r.difficulty,
                    instructions: r.instructions, mediaURL: r.mediaURL, caution: r.caution
                ))
            }
        }
        do {
            try context.save()
        } catch {
            Logger(subsystem: "com.jasonlu.breath", category: "exerciseSync").warning("Upsert save failed: \(error)")
        }
    }
}

// MARK: - Root routing view

struct RootView: View {
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !auth.isSignedIn {
                AuthView()
            } else if auth.needsUnlock {
                AppLockView()
            } else {
                RegistrationGate { HomeView() }
            }
        }
        .overlay(alignment: .top) { BackendSyncBanner() }
        .animation(.easeInOut(duration: 0.35), value: auth.isSignedIn)
        .animation(.easeInOut(duration: 0.35), value: auth.needsUnlock)
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { ensureUserProfile() }
        }
        .onChange(of: auth.displayName) { _, _ in syncProfileDisplayName() }
        .onChange(of: auth.isBackendAuthenticated) { _, authenticated in
            if authenticated { Task { await pullRemoteProfile() }; syncRoutinesAndSessions() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Foreground trigger for the sync engine — catches anything
            // that piled up in the outbox while the app was backgrounded or
            // offline (SyncOutbox.enqueue already pushes best-effort at
            // write time; this is the fallback/reconnect path).
            if phase == .active { syncRoutinesAndSessions() }
        }
        .onAppear {
            if auth.isSignedIn { ensureUserProfile(); syncProfileDisplayName() }
            if auth.isBackendAuthenticated { Task { await pullRemoteProfile() }; syncRoutinesAndSessions() }
        }
    }

    /// Drains any pending routine/session writes, then pulls the remote sets
    /// down and merges — in that order, so a local edit still in the outbox
    /// gets pushed before the pull runs and could otherwise treat it as
    /// stale. See SyncEngine.
    private func syncRoutinesAndSessions() {
        guard auth.isBackendAuthenticated else { return }
        Task {
            await SyncEngine.shared.drain(context: modelContext)
            await SyncEngine.shared.pullRemote(context: modelContext)
        }
    }

    // MARK: - Create profile on first sign-in

    private func ensureUserProfile() {
        UserProfile.dedupe(in: modelContext)

        let descriptor = FetchDescriptor<UserProfile>()
        guard let existing = try? modelContext.fetch(descriptor), existing.isEmpty else {
            #if DEBUG
            if let profile = try? modelContext.fetch(descriptor).first { applyUITestProfileSeed(to: profile) }
            #endif
            return
        }
        let name = auth.displayName.isEmpty ? "User" : auth.displayName
        // Keyed by the anonymous UUID so guest and signed-in users work the
        // same way, and the email never doubles as an identifier.
        let profile = UserProfile(profileID: auth.anonymousID, displayName: name)
        modelContext.insert(profile)
        #if DEBUG
        applyUITestProfileSeed(to: profile)
        #endif
        do {
            try modelContext.save()
        } catch {
            Logger(subsystem: "com.jasonlu.breath", category: "profile").warning("Profile save failed: \(error)")
        }
    }

    #if DEBUG
    /// Debug-only launch-argument seeding for UI verification, e.g.
    /// `-uiTestSeedPoints 200 -uiTestSeedSavers 0 -uiTestSeedSpent 0
    /// -uiTestSeedStreak 5 -uiTestSeedBreakDaysAgo 3`. No-op without the args.
    private func applyUITestProfileSeed(to profile: UserProfile) {
        let d = UserDefaults.standard
        var changed = false
        if d.object(forKey: "uiTestSeedPoints") != nil { profile.totalPoints = d.integer(forKey: "uiTestSeedPoints"); changed = true }
        if d.object(forKey: "uiTestSeedSpent") != nil { profile.pointsSpent = d.integer(forKey: "uiTestSeedSpent"); changed = true }
        if d.object(forKey: "uiTestSeedSavers") != nil { profile.streakFreezeTokens = d.integer(forKey: "uiTestSeedSavers"); changed = true }
        if d.object(forKey: "uiTestSeedStreak") != nil { profile.streak = d.integer(forKey: "uiTestSeedStreak"); changed = true }
        if d.object(forKey: "uiTestSeedBreakDaysAgo") != nil {
            let days = d.integer(forKey: "uiTestSeedBreakDaysAgo")
            profile.lastSessionDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())
            profile.pendingStreakBreak = 0
            changed = true
        }
        if changed { try? modelContext.save() }
    }
    #endif

    /// The local `UserProfile` is created at sign-in, before the name step runs
    /// (so it starts as "User"/"Apple User"). Keep it in step with the name the
    /// user entered or that was restored from Supabase — SessionRecorder uploads
    /// `profile.displayName` to the leaderboard row.
    private func syncProfileDisplayName() {
        guard auth.isSignedIn, !auth.isGuest, !auth.displayName.isEmpty,
              let profile = try? modelContext.fetch(FetchDescriptor<UserProfile>()).first,
              profile.displayName != auth.displayName else { return }
        profile.displayName = auth.displayName
        do {
            try modelContext.save()
        } catch {
            Logger(subsystem: "com.jasonlu.breath", category: "profile").warning("Profile name sync failed: \(error)")
        }
    }

    // MARK: - Pull remote stats on sign-in (cross-device streak/points/minutes)

    /// Local storage is device-only (no CloudKit — see `sharedModelContainer`),
    /// so Supabase's `profiles` row is the only channel a streak/points/minutes
    /// earned on another device can travel through. `SessionRecorder` already
    /// uploads after every session; this is the missing other half — pull the
    /// row back down and fold it into the local `UserProfile` whenever a
    /// Supabase Auth session lands (sign-in, or a session restored on cold
    /// launch). Takes the max of each stat, same reconciliation policy as
    /// `UserProfile.dedupe`, so a device that's behind catches up without a
    /// device that's ahead (but hasn't uploaded yet) ever losing progress.
    private func pullRemoteProfile() async {
        #if DEBUG
        // Seeded UI-test runs must not merge a real account's remote profile.
        if UserDefaults.standard.dictionaryRepresentation().keys.contains(where: { $0.hasPrefix("uiTestSeed") }) { return }
        #endif
        let log = Logger(subsystem: "com.jasonlu.breath", category: "profile")
        guard SupabaseService.isConfigured, auth.isBackendAuthenticated else {
            log.debug("pullRemoteProfile: skipped (configured=\(SupabaseService.isConfigured), backendAuthenticated=\(auth.isBackendAuthenticated))")
            return
        }
        let remote: RemoteProfile?
        do {
            remote = try await SupabaseService.shared.fetchProfile(id: auth.backendID)
        } catch {
            log.warning("pullRemoteProfile: fetch failed for id=\(auth.backendID, privacy: .public): \(error)")
            return
        }
        guard let remote else {
            log.debug("pullRemoteProfile: no remote row for id=\(auth.backendID, privacy: .public)")
            return
        }
        guard let profile = try? modelContext.fetch(FetchDescriptor<UserProfile>()).first else {
            log.warning("pullRemoteProfile: no local UserProfile row to merge into")
            return
        }
        log.debug("pullRemoteProfile: local streak=\(profile.streak) remote streak=\(remote.streak)")

        profile.mergeRemote(remote)
        do {
            try modelContext.save()
        } catch {
            Logger(subsystem: "com.jasonlu.breath", category: "profile").warning("Remote profile merge save failed: \(error)")
        }
    }
}
