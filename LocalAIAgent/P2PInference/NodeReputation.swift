import Foundation

/// Tracks and calculates a DePIN node's reputation score (0-100).
///
/// Score components:
/// - Uptime ratio (30%): total active time / total tracked time
/// - Average response quality (25%): mean confidence scores
/// - Average response speed (20%): faster = higher score
/// - Query success rate (25%): successful / total queries
///
/// High-reputation nodes receive query priority from LedgerServer.
@MainActor
final class NodeReputation: ObservableObject {
    static let shared = NodeReputation()

    // MARK: - Published Properties

    /// Overall reputation score (0-100)
    @Published private(set) var score: Double = 50.0

    /// Uptime as a percentage (0-100)
    @Published private(set) var uptimePercentage: Double = 0.0

    /// Average quality of responses (0-1 confidence)
    @Published private(set) var avgQuality: Double = 0.0

    /// Success rate (0-1)
    @Published private(set) var successRate: Double = 0.0

    /// Average response time in milliseconds
    @Published private(set) var avgResponseTimeMs: Double = 0.0

    // MARK: - Private Properties

    private var metrics: ReputationMetrics
    private let persistenceKey = "node_reputation_metrics"
    private var uptimeTimer: Timer?
    private var sessionStartTime: Date?

    // MARK: - Constants

    private static let uptimeWeight: Double = 0.30
    private static let qualityWeight: Double = 0.25
    private static let speedWeight: Double = 0.20
    private static let successWeight: Double = 0.25

    // Speed scoring: responses faster than this get full marks
    private static let excellentSpeedMs: Double = 1000.0
    private static let goodSpeedMs: Double = 3000.0
    private static let maxSpeedMs: Double = 10000.0

    // MARK: - Init

    private init() {
        self.metrics = ReputationMetrics()
        loadMetrics()
        recalculate()
    }

    // MARK: - Public API

    /// Record a successful query response.
    func recordSuccess(confidence: Double, responseTimeMs: Double) {
        metrics.totalQueries += 1
        metrics.successfulQueries += 1
        metrics.totalConfidence += confidence
        metrics.totalResponseTimeMs += responseTimeMs

        recalculate()
        saveMetrics()
    }

    /// Record a failed query (timeout, error, etc.)
    func recordFailure() {
        metrics.totalQueries += 1

        recalculate()
        saveMetrics()
    }

    /// Start tracking uptime (called when node activates).
    func startUptimeTracking() {
        sessionStartTime = Date()
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateUptime()
            }
        }
    }

    /// Stop tracking uptime (called when node deactivates).
    func stopUptimeTracking() {
        updateUptime()
        uptimeTimer?.invalidate()
        uptimeTimer = nil
        sessionStartTime = nil
    }

    /// Get reputation data as a TXT record dictionary for Bonjour advertisement.
    func txtRecordEntries() -> [String: String] {
        [
            "reputation": String(format: "%.0f", score),
            "uptime": String(format: "%.0f", uptimePercentage),
            "successRate": String(format: "%.2f", successRate),
            "avgSpeed": String(format: "%.0f", avgResponseTimeMs)
        ]
    }

    /// Reset all metrics (for testing or fresh start).
    func resetMetrics() {
        metrics = ReputationMetrics()
        recalculate()
        saveMetrics()
    }

    // MARK: - Private Methods

    private func updateUptime() {
        guard let start = sessionStartTime else { return }
        let sessionSeconds = Date().timeIntervalSince(start)
        // Add session time to total active time
        metrics.totalActiveSeconds += sessionSeconds
        metrics.totalTrackedSeconds += sessionSeconds
        sessionStartTime = Date() // Reset for next interval

        recalculate()
        saveMetrics()
    }

    private func recalculate() {
        // 1. Uptime score (0-100)
        if metrics.totalTrackedSeconds > 0 {
            uptimePercentage = min(100, (metrics.totalActiveSeconds / metrics.totalTrackedSeconds) * 100)
        } else {
            uptimePercentage = 0
        }
        let uptimeScore = uptimePercentage

        // 2. Quality score (0-100)
        if metrics.successfulQueries > 0 {
            avgQuality = metrics.totalConfidence / Double(metrics.successfulQueries)
        } else {
            avgQuality = 0
        }
        let qualityScore = avgQuality * 100

        // 3. Speed score (0-100)
        if metrics.successfulQueries > 0 {
            avgResponseTimeMs = metrics.totalResponseTimeMs / Double(metrics.successfulQueries)
        } else {
            avgResponseTimeMs = 0
        }
        let speedScore: Double
        if avgResponseTimeMs <= 0 || metrics.successfulQueries == 0 {
            speedScore = 50 // neutral if no data
        } else if avgResponseTimeMs <= Self.excellentSpeedMs {
            speedScore = 100
        } else if avgResponseTimeMs <= Self.goodSpeedMs {
            // Linear interpolation: 100 -> 70
            let ratio = (avgResponseTimeMs - Self.excellentSpeedMs) / (Self.goodSpeedMs - Self.excellentSpeedMs)
            speedScore = 100 - (ratio * 30)
        } else if avgResponseTimeMs <= Self.maxSpeedMs {
            // Linear interpolation: 70 -> 20
            let ratio = (avgResponseTimeMs - Self.goodSpeedMs) / (Self.maxSpeedMs - Self.goodSpeedMs)
            speedScore = 70 - (ratio * 50)
        } else {
            speedScore = 20
        }

        // 4. Success rate score (0-100)
        if metrics.totalQueries > 0 {
            successRate = Double(metrics.successfulQueries) / Double(metrics.totalQueries)
        } else {
            successRate = 0
        }
        let successScore = successRate * 100

        // Weighted average
        score = (uptimeScore * Self.uptimeWeight)
              + (qualityScore * Self.qualityWeight)
              + (speedScore * Self.speedWeight)
              + (successScore * Self.successWeight)

        // Clamp to 0-100
        score = min(100, max(0, score))
    }

    // MARK: - Persistence

    private func loadMetrics() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let decoded = try? JSONDecoder().decode(ReputationMetrics.self, from: data) else {
            return
        }
        metrics = decoded
    }

    private func saveMetrics() {
        guard let data = try? JSONEncoder().encode(metrics) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }
}

// MARK: - Metrics Data

private struct ReputationMetrics: Codable {
    var totalQueries: Int = 0
    var successfulQueries: Int = 0
    var totalConfidence: Double = 0.0
    var totalResponseTimeMs: Double = 0.0
    var totalActiveSeconds: Double = 0.0
    var totalTrackedSeconds: Double = 0.0
}
