#if targetEnvironment(macCatalyst)
import SwiftUI

// MARK: - Mac Menu Bar Commands

struct ElioCommands: Commands {
    @FocusedValue(\.newConversation) private var newConversation
    @FocusedValue(\.showSettings) private var showSettings
    @FocusedValue(\.showConversationList) private var showConversationList
    @FocusedValue(\.showChatWebConnect) private var showChatWebConnect
    @FocusedValue(\.showDePINDashboard) private var showDePINDashboard
    @FocusedValue(\.stopGeneration) private var stopGeneration
    @FocusedValue(\.isGenerating) private var isGenerating

    var body: some Commands {
        // MARK: File Menu
        CommandGroup(after: .newItem) {
            Button("New Conversation") {
                newConversation?()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(newConversation == nil)
        }

        // MARK: Edit Menu — Stop Generation
        CommandGroup(after: .undoRedo) {
            if isGenerating == true {
                Divider()
                Button("Stop Generation") {
                    stopGeneration?()
                }
                .keyboardShortcut(".", modifiers: .command)
            }
        }

        // MARK: View Menu
        CommandGroup(after: .toolbar) {
            Button("Show Conversations") {
                showConversationList?()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(showConversationList == nil)

            Divider()

            Button("Connect to ChatWeb") {
                showChatWebConnect?()
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(showChatWebConnect == nil)

            Button("DePIN Dashboard") {
                showDePINDashboard?()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(showDePINDashboard == nil)
        }

        // MARK: Window Menu — Settings
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                showSettings?()
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(showSettings == nil)
        }

        // MARK: Help Menu
        CommandGroup(replacing: .help) {
            Button("Elio Chat Help") {
                if let url = URL(string: "https://elio.love/help") {
                    UIApplication.shared.open(url)
                }
            }
            .keyboardShortcut("?", modifiers: .command)

            Divider()

            Button("Feedback & Support") {
                if let url = URL(string: "https://elio.love/support") {
                    UIApplication.shared.open(url)
                }
            }

            Button("Privacy Policy") {
                if let url = URL(string: "https://elio.love/privacy") {
                    UIApplication.shared.open(url)
                }
            }
        }
    }
}
#endif
