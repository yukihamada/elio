import Foundation

/// Reports processed queries to chatweb.ai DePIN API to earn on-chain ENAI rewards.
/// Fire-and-forget: failures are logged but do not affect local reward tracking.
enum DePINReporter {
    private static let apiURL = URL(string: "https://chatweb.ai/api/v1/depin/report")!

    /// Report a processed query to earn 1 ENAI reward.
    /// - Parameters:
    ///   - nodeWallet: Solana wallet address of this node (receives ENAI)
    ///   - queryHash: UUID string of the processed query
    ///   - proofTimestamp: Unix timestamp when the query was completed
    static func reportQuery(
        nodeWallet: String,
        queryHash: String,
        proofTimestamp: Int
    ) async {
        guard !nodeWallet.isEmpty else {
            // No wallet connected; skip reporting
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "node_wallet": nodeWallet,
            "query_hash": queryHash,
            "proof_timestamp": proofTimestamp
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                if let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let txSig = result["reward_tx"] as? String ?? ""
                    let enaiSent = result["enai_sent"] as? Double ?? 0
                    if enaiSent > 0 {
                        print("[DePIN] ✅ ENAI reward: \(enaiSent) ENAI (tx: \(txSig.prefix(16))...)")
                    }
                }
            } else if let http = response as? HTTPURLResponse {
                print("[DePIN] ⚠️ Report returned HTTP \(http.statusCode) for query \(queryHash.prefix(8))")
            }
        } catch {
            // Network errors are non-fatal; local reward is already recorded
            print("[DePIN] ⚠️ Report failed: \(error.localizedDescription)")
        }
    }
}
