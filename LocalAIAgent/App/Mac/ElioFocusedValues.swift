#if targetEnvironment(macCatalyst)
import SwiftUI

// MARK: - Focused Values for Menu ↔ Window communication

struct NewConversationFocusedValueKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ShowSettingsFocusedValueKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ShowConversationListFocusedValueKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ShowChatWebConnectFocusedValueKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct ShowDePINDashboardFocusedValueKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct StopGenerationFocusedValueKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct IsGeneratingFocusedValueKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var newConversation: (() -> Void)? {
        get { self[NewConversationFocusedValueKey.self] }
        set { self[NewConversationFocusedValueKey.self] = newValue }
    }
    var showSettings: (() -> Void)? {
        get { self[ShowSettingsFocusedValueKey.self] }
        set { self[ShowSettingsFocusedValueKey.self] = newValue }
    }
    var showConversationList: (() -> Void)? {
        get { self[ShowConversationListFocusedValueKey.self] }
        set { self[ShowConversationListFocusedValueKey.self] = newValue }
    }
    var showChatWebConnect: (() -> Void)? {
        get { self[ShowChatWebConnectFocusedValueKey.self] }
        set { self[ShowChatWebConnectFocusedValueKey.self] = newValue }
    }
    var showDePINDashboard: (() -> Void)? {
        get { self[ShowDePINDashboardFocusedValueKey.self] }
        set { self[ShowDePINDashboardFocusedValueKey.self] = newValue }
    }
    var stopGeneration: (() -> Void)? {
        get { self[StopGenerationFocusedValueKey.self] }
        set { self[StopGenerationFocusedValueKey.self] = newValue }
    }
    var isGenerating: Bool? {
        get { self[IsGeneratingFocusedValueKey.self] }
        set { self[IsGeneratingFocusedValueKey.self] = newValue }
    }
}
#endif
