import SwiftUI
#if !targetEnvironment(macCatalyst)
import WidgetKit
#endif

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
                    #if targetEnvironment(macCatalyst)
                    Task { await appState.macStartupSetup() }
                    #endif
                }
                .onChange(of: appState.currentConversation) { _, _ in
                    updateWidgetData()
                }
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 900, height: 700)
        #endif
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

        case "schedule":
            // Quick action: Check today's schedule
            appState.pendingQuickQuestion = "今日の予定を教えて"

        case "weather":
            // Quick action: Check weather
            appState.pendingQuickQuestion = "今日の天気は？"

        case "reminder":
            // Quick action: Create reminder
            appState.pendingQuickQuestion = "リマインダーを作成して"

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
        #if !targetEnvironment(macCatalyst)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
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
