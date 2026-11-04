import SwiftUI

/// Surfaces `AuthManager.backendSyncFailed`/`justReconnected` — the state
/// where Apple sign-in succeeded locally but the Supabase exchange didn't
/// (see AuthManager.exchangeAppleToken). Non-blocking: the user keeps using
/// the app locally either way, this just makes the degraded state visible
/// and gives them a way to retry without signing out.
///
/// Mounted once at the root (`RootView`) via `.overlay(alignment: .top)` so
/// it's visible from any tab, not tied to the Profile/Account screen.
struct BackendSyncBanner: View {
    @EnvironmentObject private var auth: AuthManager

    @State private var isRetrying = false
    /// Locally dismissed for this occurrence of the failure. Reset whenever
    /// `backendSyncFailed` transitions back to true, so a *new* failure
    /// (e.g. after a fresh sign-in) shows again even if a previous one was
    /// dismissed.
    @State private var dismissed = false
    @State private var showConnected = false

    var body: some View {
        VStack {
            if auth.backendSyncFailed && !dismissed {
                failureBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if showConnected {
                connectedBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.backendSyncFailed)
        .animation(.easeInOut(duration: 0.25), value: showConnected)
        .onChange(of: auth.backendSyncFailed) { _, failed in
            if failed { dismissed = false }
        }
        .onChange(of: auth.justReconnected) { _, reconnected in
            guard reconnected else { return }
            auth.justReconnected = false
            showConnected = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                showConnected = false
            }
        }
    }

    private var failureBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.pastelPeach)
            Text("Signed in, but sync isn't connected")
                .font(.luminaLabel)
                .foregroundStyle(Color.luminaOnSurface)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button {
                Task {
                    isRetrying = true
                    await auth.retryBackendConnection()
                    isRetrying = false
                }
            } label: {
                if isRetrying {
                    ProgressView()
                        .tint(Color.luminaOnPrimary)
                        .frame(minHeight: 34)
                        .padding(.horizontal, 14)
                } else {
                    Text("Retry")
                }
            }
            .buttonStyle(LuminaPillButtonStyle(compact: true))
            .disabled(isRetrying)

            Button {
                dismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.luminaLabel)
                    .foregroundStyle(Color.luminaOnSurfaceVariant)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(Color.luminaContainer, in: RoundedRectangle(cornerRadius: LuminaRadius.badge, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Signed in, but sync isn't connected")
    }

    private var connectedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.pastelMint)
            Text("Connected")
                .font(.luminaLabel)
                .foregroundStyle(Color.luminaOnSurface)
        }
        .padding(12)
        .background(Color.luminaContainer, in: RoundedRectangle(cornerRadius: LuminaRadius.badge, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Failed") {
    let auth = AuthManager.shared
    return ZStack {
        Color.luminaSurface.ignoresSafeArea()
        BackendSyncBanner()
    }
    .environmentObject(auth)
}
