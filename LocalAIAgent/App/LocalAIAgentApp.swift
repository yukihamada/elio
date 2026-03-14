import SwiftUI
#if !targetEnvironment(macCatalyst)
import WidgetKit
#endif

// MARK: - App Delegate (macCatalyst state restoration fix)

class ElioAppDelegate: NSObject, UIApplicationDelegate {
    /// Prevent macCatalyst from restoring saved scene state,
    /// which can cause EnvironmentObject crashes on launch.
    func application(_ application: UIApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool {
        return false
    }

    func application(_ application: UIApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool {
        return false
    }
}

@main
struct LocalAIAgentApp: App {
    @UIApplicationDelegateAdaptor(ElioAppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var syncManager = SyncManager.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(hasCompletedOnboarding: $hasCompletedOnboarding)
                .environmentObject(appState)
                .environmentObject(themeManager)
                .environmentObject(syncManager)
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
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    handleScenePhaseChange(from: oldPhase, to: newPhase)
                }
                .onAppear {
                    // Start monitoring for server auto-start
                    startServerMonitoring()
                    #if !targetEnvironment(macCatalyst)
                    // iPhone: start Bonjour browsing to discover Mac peers
                    ChatModeManager.shared.p2p?.startBrowsing()
                    #endif

                    #if targetEnvironment(macCatalyst)
                    // Mac: Keep app running when last window is closed (DePIN node stays active in Dock)
                    configureMacWindowBehavior()
                    #endif
                }
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 900, height: 700)
        .commands { ElioCommands() }
        #endif
    }

    #if targetEnvironment(macCatalyst)
    /// Configure Mac Catalyst to keep app running in Dock when window is closed.
    private func configureMacWindowBehavior() {
        // UIKit bridge: applicationShouldTerminateAfterLastWindowClosed = false
        // On macCatalyst, this keeps the DePIN node running even when the window is closed.
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.sizeRestrictions?.minimumSize = CGSize(width: 600, height: 500)
        }
    }
    #endif

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

        case "shared":
            // Open shared conversation in browser: elio://shared/{id}
            if let shareId = url.pathComponents.dropFirst().first, !shareId.isEmpty {
                let shareURL = URL(string: "https://elio.love/s/\(shareId)")!
                UIApplication.shared.open(shareURL)
            }

        default:
            break
        }
    }

    /// Handle scene phase changes (foreground/background transitions)
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // App became active (foreground)
            if oldPhase == .background {
                logInfo("App", "App returned to foreground")
                #if !targetEnvironment(macCatalyst)
                ChatModeManager.shared.p2p?.startBrowsing()
                #endif
            }

        case .inactive:
            // App is transitioning (e.g., during push notification, control center)
            // Don't do anything heavy here
            break

        case .background:
            // App went to background
            logInfo("App", "App entered background")

            #if targetEnvironment(macCatalyst)
            // Mac: Keep P2P/DePIN server running in background (Dock mode)
            // Only save conversations, don't stop generation or networking
            Task {
                await appState.saveConversations()
            }
            #else
            // iOS: Stop generation but keep model loaded
            if appState.isGenerating {
                appState.shouldStopGeneration = true
            }

            Task {
                await appState.saveConversations()
            }

            // Note: We intentionally DON'T unload the model here
            // iOS will automatically purge memory if needed
            ChatModeManager.shared.p2p?.stopBrowsing()
            #endif

        @unknown default:
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

    /// Start monitoring for server auto-start
    private func startServerMonitoring() {
        #if os(iOS)
        // Monitor battery state changes
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await self.handleBatteryStateChange()
            }
        }

        // Monitor battery level changes
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await self.handleBatteryLevelChange()
            }
        }

        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Check current state
        Task { @MainActor in
            await self.handleBatteryStateChange()
        }
        #endif
    }

    #if os(iOS)
    /// Handle battery state changes (plugged/unplugged)
    private func handleBatteryStateChange() async {
        let config = InferenceServerConfig.shared
        guard config.autoStartWhenCharging else { return }

        let isCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full

        if isCharging && appState.isModelLoaded {
            // Start server when charging
            await config.startServerIfNeeded()
        } else if !isCharging {
            // Stop server when unplugged
            config.stopServer()
        }
    }

    /// Handle battery level changes
    private func handleBatteryLevelChange() async {
        let config = InferenceServerConfig.shared
        let batteryLevel = UIDevice.current.batteryLevel

        // Stop server if battery drops below threshold
        if batteryLevel >= 0 && Int(batteryLevel * 100) < config.autoStopBatteryThreshold {
            config.stopServer()
        }
    }
    #endif
}

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var syncManager: SyncManager
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
            .sheet(isPresented: $syncManager.showUpgradePrompt) {
                UpgradeElioProView()
                    .environmentObject(syncManager)
            }
    }
}
