import Foundation
import Combine

/// Barter Board Manager - P2P marketplace for trading goods
/// Manages listings, matching, and trust scores in mesh network
@MainActor
final class BarterBoardManager: ObservableObject {
    static let shared = BarterBoardManager()

    // MARK: - Published Properties

    @Published var listings: [BarterListing] = []
    @Published var myListings: [BarterListing] = []
    @Published var trustScores: [String: TrustScore] = [:]
    @Published var matches: [BarterMatch] = []

    // MARK: - Private Properties

    private let deviceIdKey = "barter_device_id"
    private let listingsFileURL: URL
    private let trustScoresFileURL: URL
    private var meshP2PManager: MeshP2PManager?

    // MARK: - Initialization

    private init() {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let barterPath = documentsPath.appendingPathComponent("Barter", isDirectory: true)

        if !fileManager.fileExists(atPath: barterPath.path) {
            try? fileManager.createDirectory(at: barterPath, withIntermediateDirectories: true)
        }

        listingsFileURL = barterPath.appendingPathComponent("listings.json")
        trustScoresFileURL = barterPath.appendingPathComponent("trust_scores.json")

        loadListings()
        loadTrustScores()
    }

    // MARK: - Listing Management

    /// Post a new barter listing
    func postListing(have: String, want: String, location: String?, notes: String?) async throws {
        let listing = BarterListing(
            id: UUID(),
            deviceId: getDeviceId(),
            deviceName: getDeviceName(),
            have: have,
            want: want,
            location: location,
            notes: notes,
            createdAt: Date(),
            status: .active
        )

        myListings.append(listing)
        listings.append(listing)

        try await saveListings()

        // Broadcast to mesh network
        await broadcastListing(listing)
    }

    /// Cancel a listing
    func cancelListing(id: UUID) async throws {
        if let index = myListings.firstIndex(where: { $0.id == id }) {
            myListings[index].status = .cancelled
        }

        if let index = listings.firstIndex(where: { $0.id == id }) {
            listings[index].status = .cancelled
        }

        try await saveListings()
    }

    /// Complete a transaction
    func completeTransaction(listingId: UUID, partnerDeviceId: String, rating: TransactionRating) async throws {
        // Mark listing as completed
        if let index = myListings.firstIndex(where: { $0.id == listingId }) {
            myListings[index].status = .completed
        }

        if let index = listings.firstIndex(where: { $0.id == listingId }) {
            listings[index].status = .completed
        }

        // Update trust score
        updateTrustScore(deviceId: partnerDeviceId, rating: rating)

        try await saveListings()
        try await saveTrustScores()
    }

    // MARK: - Matching

    /// Find potential matches for a listing
    func findMatches(for listing: BarterListing) -> [BarterMatch] {
        var potentialMatches: [BarterMatch] = []

        for otherListing in listings where otherListing.id != listing.id && otherListing.status == .active {
            // Check if wants and haves match
            if isMatch(listing: listing, with: otherListing) {
                let matchScore = calculateMatchScore(listing: listing, with: otherListing)
                let trustScore = trustScores[otherListing.deviceId]?.score ?? 0.5

                let match = BarterMatch(
                    id: UUID(),
                    yourListing: listing,
                    theirListing: otherListing,
                    matchScore: matchScore,
                    trustScore: trustScore,
                    distance: otherListing.location
                )

                potentialMatches.append(match)
            }
        }

        // Sort by match score and trust score
        potentialMatches.sort { match1, match2 in
            let score1 = match1.matchScore * 0.6 + Float(match1.trustScore) * 0.4
            let score2 = match2.matchScore * 0.6 + Float(match2.trustScore) * 0.4
            return score1 > score2
        }

        return potentialMatches
    }

    private func isMatch(listing: BarterListing, with other: BarterListing) -> Bool {
        let listingWants = listing.want.lowercased()
        let otherHas = other.have.lowercased()
        let listingHas = listing.have.lowercased()
        let otherWants = other.want.lowercased()

        // Simple keyword matching
        return listingWants.contains(where: { otherHas.contains(String($0)) }) ||
               listingHas.contains(where: { otherWants.contains(String($0)) })
    }

    private func calculateMatchScore(listing: BarterListing, with other: BarterListing) -> Float {
        var score: Float = 0

        // Exact match bonus
        if listing.want.lowercased() == other.have.lowercased() {
            score += 0.5
        }

        if listing.have.lowercased() == other.want.lowercased() {
            score += 0.5
        }

        return min(score, 1.0)
    }

    /// AI-powered match suggestions
    func getAISuggestions(for listing: BarterListing) async -> String {
        let matches = findMatches(for: listing)

        if matches.isEmpty {
            return "現在、マッチする物々交換はありません。\n\n提案: \(listing.have)は需要が高いので、もう少し待てば取引相手が見つかるかもしれません。"
        }

        var suggestions = "マッチした取引を\(matches.count)件見つけました：\n\n"

        for (index, match) in matches.prefix(3).enumerated() {
            let trustEmoji = match.trustScore > 0.7 ? "🌟" : match.trustScore > 0.5 ? "⭐️" : "❓"
            suggestions += "\(index + 1). \(trustEmoji) \(match.theirListing.deviceName)\n"
            suggestions += "   提供: \(match.theirListing.have)\n"
            suggestions += "   希望: \(match.theirListing.want)\n"
            suggestions += "   信頼度: \(Int(match.trustScore * 100))%\n"
            if let distance = match.distance {
                suggestions += "   場所: \(distance)\n"
            }
            suggestions += "\n"
        }

        return suggestions
    }

    // MARK: - Trust Score

    private func updateTrustScore(deviceId: String, rating: TransactionRating) {
        var score = trustScores[deviceId] ?? TrustScore(deviceId: deviceId)

        switch rating {
        case .excellent:
            score.positiveRatings += 2
        case .good:
            score.positiveRatings += 1
        case .neutral:
            break
        case .bad:
            score.negativeRatings += 1
        case .fraud:
            score.negativeRatings += 3
        }

        trustScores[deviceId] = score
    }

    func getTrustScore(for deviceId: String) -> TrustScore? {
        return trustScores[deviceId]
    }

    // MARK: - P2P Mesh Sync

    private func broadcastListing(_ listing: BarterListing) async {
        // TODO: Implement mesh network broadcast
        // For now, just add to local listings
        print("[Barter] Broadcasting listing: \(listing.have) → \(listing.want)")
    }

    func receiveListing(_ listing: BarterListing) async {
        // Received from mesh network
        if !listings.contains(where: { $0.id == listing.id }) {
            listings.append(listing)
            try? await saveListings()

            // Check for matches with my listings
            for myListing in myListings where myListing.status == .active {
                if isMatch(listing: myListing, with: listing) {
                    // Notify user of potential match
                    print("[Barter] New match found for: \(myListing.have)")
                }
            }
        }
    }

    // MARK: - Persistence

    private func saveListings() async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let allListings = ListingsContainer(
            myListings: myListings,
            allListings: listings
        )

        let data = try encoder.encode(allListings)
        try data.write(to: listingsFileURL)
    }

    private func loadListings() {
        guard FileManager.default.fileExists(atPath: listingsFileURL.path),
              let data = try? Data(contentsOf: listingsFileURL) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let container = try? decoder.decode(ListingsContainer.self, from: data) {
            myListings = container.myListings
            listings = container.allListings
        }
    }

    private func saveTrustScores() async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(trustScores)
        try data.write(to: trustScoresFileURL)
    }

    private func loadTrustScores() {
        guard FileManager.default.fileExists(atPath: trustScoresFileURL.path),
              let data = try? Data(contentsOf: trustScoresFileURL) else {
            return
        }

        if let scores = try? JSONDecoder().decode([String: TrustScore].self, from: data) {
            trustScores = scores
        }
    }

    // MARK: - Helpers

    private func getDeviceId() -> String {
        if let existingId = UserDefaults.standard.string(forKey: deviceIdKey) {
            return existingId
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: deviceIdKey)
        return newId
    }

    private func getDeviceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return "Unknown Device"
        #endif
    }
}

// MARK: - Supporting Types

struct BarterListing: Identifiable, Codable, Equatable {
    let id: UUID
    let deviceId: String
    let deviceName: String
    let have: String
    let want: String
    let location: String?
    let notes: String?
    let createdAt: Date
    var status: ListingStatus

    enum ListingStatus: String, Codable {
        case active, completed, cancelled
    }
}

struct BarterMatch: Identifiable {
    let id: UUID
    let yourListing: BarterListing
    let theirListing: BarterListing
    let matchScore: Float
    let trustScore: Float
    let distance: String?
}

struct TrustScore: Codable {
    let deviceId: String
    var positiveRatings: Int = 0
    var negativeRatings: Int = 0

    var totalRatings: Int {
        positiveRatings + negativeRatings
    }

    var score: Float {
        guard totalRatings > 0 else { return 0.5 } // Neutral for new users
        return Float(positiveRatings) / Float(totalRatings)
    }

    var displayScore: String {
        if totalRatings == 0 {
            return "新規"
        }
        return String(format: "%.0f%%", score * 100)
    }

    var trustLevel: TrustLevel {
        if totalRatings < 3 {
            return .new
        } else if score >= 0.8 {
            return .excellent
        } else if score >= 0.6 {
            return .good
        } else if score >= 0.4 {
            return .neutral
        } else {
            return .low
        }
    }

    enum TrustLevel {
        case new, excellent, good, neutral, low

        var emoji: String {
            switch self {
            case .new: return "🆕"
            case .excellent: return "🌟"
            case .good: return "⭐️"
            case .neutral: return "❓"
            case .low: return "⚠️"
            }
        }

        var displayName: String {
            switch self {
            case .new: return "新規"
            case .excellent: return "信頼できる"
            case .good: return "良好"
            case .neutral: return "普通"
            case .low: return "注意"
            }
        }
    }
}

enum TransactionRating: String, CaseIterable {
    case excellent = "非常に良い"
    case good = "良い"
    case neutral = "普通"
    case bad = "悪い"
    case fraud = "詐欺・トラブル"

    var value: Int {
        switch self {
        case .excellent: return 2
        case .good: return 1
        case .neutral: return 0
        case .bad: return -1
        case .fraud: return -3
        }
    }
}

private struct ListingsContainer: Codable {
    let myListings: [BarterListing]
    let allListings: [BarterListing]
}
