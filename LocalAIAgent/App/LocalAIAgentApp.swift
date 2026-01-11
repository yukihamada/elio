import SwiftUI
import WidgetKit

@main
struct LocalAIAgentApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var themeManager = ThemeManager()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            ContentView(hasCompletedOnboarding: $hasCompletedOnboarding)
                .environmentObject(appState)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.colorScheme)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onChange(of: appState.isModelLoaded) { _, _ in
                    updateWidgetData()
                }
                .onChange(of: appState.currentConversation) { _, _ in
                    updateWidgetData()
                }
        }
    }

    /// Handle deep links from widget
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "elio" else { return }

        switch url.host {
        case "ask":
            // Check for pending question from widget
            if let question = SharedDataManager.loadPendingQuestion() {
                appState.pendingQuickQuestion = question
            }
            // New chat will be created when user sends

        case "conversations":
            // Open conversations list
            appState.showConversationList = true

        case "conversation":
            // Open specific conversation (could add ID parameter)
            break

        default:
            break
        }
    }

    /// Update widget data when app state changes
    private func updateWidgetData() {
        SharedDataManager.saveAppStateSnapshot(
            modelName: appState.currentModelName,
            isModelLoaded: appState.isModelLoaded,
            recentConversation: appState.conversations.first
        )

        // Request widget refresh
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var hasCompletedOnboarding: Bool
    @State private var showingOnboarding = false

    var body: some View {
        ChatView()
            .onAppear {
                if !hasCompletedOnboarding {
                    showingOnboarding = true
                }
            }
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(appState)
            }
    }
}
