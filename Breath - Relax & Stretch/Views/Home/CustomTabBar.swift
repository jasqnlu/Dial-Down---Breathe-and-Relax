import SwiftUI

// MARK: - Custom Tab Bar
//
// Modern black restyle (seperate-main): a floating graphite bar with
// icon-only tabs. Whichever tab is active "pops out": it rises above the
// bar's top edge as a pastel circle, ringed in the page color so it reads
// as cut out of the bar. A matched-geometry circle slides between tabs.

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ScaledMetric(relativeTo: .body) private var tabIconSize: CGFloat = 19

    /// Vertical space a page must keep clear at the bottom so its content
    /// isn't covered by the bar (≈ 60pt bar + 6pt bottom padding + room).
    static let contentClearance: CGFloat = 76

    private static let barHeight: CGFloat = 60
    private static let bubbleSize: CGFloat = 48
    /// How far the active bubble rises above the bar's centerline.
    private static let popOffset: CGFloat = -20

    private struct TabItem {
        let icon: String
        let activeIcon: String
        let label: String
        let anchorID: String
        let tint: Color
    }

    private let tabs: [TabItem] = [
        TabItem(icon: "sun.max",         activeIcon: "sun.max.fill",         label: "Today",     anchorID: "tabbar.today",     tint: .pastelYellow),
        TabItem(icon: "square.grid.2x2", activeIcon: "square.grid.2x2.fill", label: "Exercises", anchorID: "tabbar.exercises", tint: .pastelBlue),
        TabItem(icon: "wind",            activeIcon: "wind",                 label: "Breathe",   anchorID: "tabbar.breathe",   tint: .pastelMint),
        TabItem(icon: "rectangle.stack", activeIcon: "rectangle.stack.fill", label: "Routines",  anchorID: "tabbar.routines",  tint: .pastelLavender),
        TabItem(icon: "person",          activeIcon: "person.fill",          label: "Profile",   anchorID: "tabbar.profile",   tint: .pastelPink),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { tabButton(index: $0) }
        }
        .frame(height: Self.barHeight)
        // Wide enough that an edge tab's bubble (plus its ring) stays inside
        // the bar's rounded corners.
        .padding(.horizontal, 14)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.luminaCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private func tabButton(index: Int) -> some View {
        let isActive = selectedTab == index
        let tab = tabs[index]

        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.72)) {
                selectedTab = index
            }
        } label: {
            ZStack {
                if isActive {
                    Circle()
                        .fill(tab.tint)
                        // Page-colored ring: the bubble looks cut out of the bar.
                        .overlay(Circle().strokeBorder(Color.luminaSurface, lineWidth: 5).padding(-5))
                        .shadow(color: tab.tint.opacity(0.35), radius: 10, y: 4)
                        .frame(width: Self.bubbleSize, height: Self.bubbleSize)
                        .matchedGeometryEffect(id: "activeBubble", in: ns)
                        .offset(y: Self.popOffset)
                }

                Image(systemName: isActive ? tab.activeIcon : tab.icon)
                    .font(.system(size: isActive ? tabIconSize + 2 : tabIconSize,
                                  weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.onPastel : Color.white.opacity(0.5))
                    .offset(y: isActive ? Self.popOffset : 0)
            }
            .frame(maxWidth: .infinity, minHeight: Self.barHeight)
            .contentShape(Rectangle())
        }
        .tourAnchor(tab.anchorID)
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Page clearance

extension View {
    /// Reserves bottom safe-area space so page content clears the floating
    /// tab bar and the Ask button resting above it. Must be applied INSIDE each tab page's NavigationStack (and
    /// inside any view pushed onto it): a safe-area inset added outside a
    /// NavigationStack is not forwarded to the stack's content, so HomeView
    /// cannot apply this once for all pages.
    func floatingTabBarClearance() -> some View {
        safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: CustomTabBar.contentClearance + AskButton.clearance)
                // Never swallow taps on content scrolled under the bar area.
                .allowsHitTesting(false)
        }
    }
}

#Preview {
    @Previewable @State var tab = 0
    VStack {
        Spacer()
        CustomTabBar(selectedTab: $tab)
        Spacer().frame(height: 24)
    }
    .background(Color(.systemGroupedBackground))
}
