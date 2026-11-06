/// How the Ask chat is shown: just the floating button, a semi-transparent side
/// panel, a shrunk pill above the tab bar, or full screen.
enum AskPanelMode: CaseIterable, Equatable {
    case closed, side, pill, full

    /// Sending a message shows its reply: a full-screen chat stays full,
    /// anything else opens the side panel.
    var afterSending: AskPanelMode { self == .full ? .full : .side }

    /// The header's expand / collapse control.
    var toggledSize: AskPanelMode { self == .full ? .side : .full }

    var showsChat: Bool { self == .side || self == .full }

    /// Tapping the floating button reopens an existing conversation; with none
    /// yet it returns nil and the ask bar opens instead.
    static func forButtonTap(hasConversation: Bool) -> AskPanelMode? {
        hasConversation ? .side : nil
    }
}
