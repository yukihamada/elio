import Foundation
import SwiftUI

/// Inference server configuration and state management
@MainActor
final class InferenceServerConfig: ObservableObject {
    static let shared = InferenceServerConfig()

    // MARK: - Published Properties

    /// Whether server is enabled
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "inferenceServerEnabled")
        }
    }

    /// Server visibility mode
    @Published var serverMode: ServerMode {
        didSet {
            UserDefaults.standard.set(serverMode.rawValue, forKey: "inferenceServerMode")
        }
    }

    /// Token price per request (0 = free)
    @Published var pricePerRequest: Int {
        didSet {
            UserDefaults.standard.set(pricePerRequest, forKey: "inferenceServerPrice")
        }
    }

    /// Auto-start server when device is charging
    @Published var autoStartWhenCharging: Bool {
        didSet {
            UserDefaults.standard.set(autoStartWhenCharging, forKey: "inferenceServerAutoCharge")
        }
    }

    /// Auto-stop when battery drops below threshold
    @Published var autoStopBatteryThreshold: Int {
        didSet {
            UserDefaults.standard.set(autoStopBatteryThreshold, forKey: "inferenceServerBatteryThreshold")
        }
    }

    /// Maximum concurrent requests
    @Published var maxConcurrentRequests: Int {
        didSet {
            UserDefaults.standard.set(maxConcurrentRequests, forKey: "inferenceServerMaxRequests")
        }
    }

    /// Allow internet connections (vs local network only)
    @Published var allowInternetConnections: Bool {
        didSet {
            UserDefaults.standard.set(allowInternetConnections, forKey: "inferenceServerInternet")
        }
    }

    // MARK: - Initialization

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "inferenceServerEnabled")
        self.serverMode = ServerMode(rawValue: UserDefaults.standard.string(forKey: "inferenceServerMode") ?? "private") ?? .private
        self.pricePerRequest = UserDefaults.standard.integer(forKey: "inferenceServerPrice")
        self.autoStartWhenCharging = UserDefaults.standard.bool(forKey: "inferenceServerAutoCharge")
        self.autoStopBatteryThreshold = UserDefaults.standard.object(forKey: "inferenceServerBatteryThreshold") as? Int ?? 20
        self.maxConcurrentRequests = UserDefaults.standard.object(forKey: "inferenceServerMaxRequests") as? Int ?? 3
        self.allowInternetConnections = UserDefaults.standard.bool(forKey: "inferenceServerInternet")
    }

    // MARK: - Server Control

    /// Start server if conditions are met
    func startServerIfNeeded() async {
        guard isEnabled else { return }

        // Check battery level
        #if os(iOS)
        let batteryLevel = await getBatteryLevel()
        if let battery = batteryLevel, battery < Float(autoStopBatteryThreshold) / 100.0 {
            print("[InferenceServer] Battery too low (\(Int(battery * 100))%), not starting")
            return
        }
        #endif

        // Start server
        do {
            try await PrivateServerManager.shared.start()
            print("[InferenceServer] Started successfully")
        } catch {
            print("[InferenceServer] Failed to start: \(error)")
        }
    }

    /// Stop server
    func stopServer() {
        PrivateServerManager.shared.stop()
        print("[InferenceServer] Stopped")
    }

    // MARK: - Helpers

    private func getBatteryLevel() async -> Float? {
        #if os(iOS)
        await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            return level >= 0 ? level : nil
        }
        #else
        return nil
        #endif
    }
}

/// Server visibility mode
enum ServerMode: String, Codable, CaseIterable, Identifiable {
    case `private` = "private"  // Only trusted devices
    case friendsOnly = "friends" // Friends + trusted
    case `public` = "public"    // Anyone can connect

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .private:
            return String(localized: "server.mode.private", defaultValue: "プライベート")
        case .friendsOnly:
            return String(localized: "server.mode.friends", defaultValue: "フレンドのみ")
        case .public:
            return String(localized: "server.mode.public", defaultValue: "パブリック")
        }
    }

    var description: String {
        switch self {
        case .private:
            return String(localized: "server.mode.private.desc", defaultValue: "明示的に信頼したデバイスのみ")
        case .friendsOnly:
            return String(localized: "server.mode.friends.desc", defaultValue: "信頼したデバイス＋フレンド")
        case .public:
            return String(localized: "server.mode.public.desc", defaultValue: "ネットワーク上の誰でもGPUを利用可能")
        }
    }

    var icon: String {
        switch self {
        case .private: return "lock.shield.fill"
        case .friendsOnly: return "person.2.fill"
        case .public: return "globe"
        }
    }

    var color: Color {
        switch self {
        case .private: return .green
        case .friendsOnly: return .blue
        case .public: return .orange
        }
    }
}
