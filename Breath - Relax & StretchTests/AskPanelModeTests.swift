import Testing
@testable import BreathRelaxStretch

/// The side chat's four presentations: closed (button), side panel, shrunk pill, full screen.
struct AskPanelModeTests {
    @Test func sendingOpensTheSideChatUnlessFull() {
        #expect(AskPanelMode.closed.afterSending == .side)
        #expect(AskPanelMode.pill.afterSending == .side)
        #expect(AskPanelMode.side.afterSending == .side)
        #expect(AskPanelMode.full.afterSending == .full, "a full-screen chat stays full")
    }

    @Test func sizeToggleSwitchesSideAndFull() {
        #expect(AskPanelMode.side.toggledSize == .full)
        #expect(AskPanelMode.full.toggledSize == .side)
    }

    @Test func onlySideAndFullShowTheChat() {
        #expect(AskPanelMode.allCases.filter(\.showsChat) == [.side, .full])
    }

    @Test func buttonTapReopensAnExistingConversation() {
        #expect(AskPanelMode.forButtonTap(hasConversation: true) == .side)
        #expect(AskPanelMode.forButtonTap(hasConversation: false) == nil, "no chat yet: the ask bar opens")
    }
}
