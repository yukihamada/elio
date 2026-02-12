import Foundation
import Network

/// Handles HTTP relay requests from P2P clients that lack internet access
/// Security: Only whitelisted domains are allowed, with rate limiting per client
@MainActor
final class InternetRelayHandler {
    static let shared = InternetRelayHandler()

    // MARK: - Security

    private let allowedDomains: Set<String> = [
        "api.chatweb.ai",
        "api.openai.com",
        "api.anthropic.com",
        "api.groq.com"
    ]

    /// Rate limit: max requests per minute per client
    private let maxRequestsPerMinute = 60
    private var clientRequestCounts: [String: (count: Int, windowStart: Date)] = [:]

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }

    // MARK: - Request Handling

    func handleRelayRequest(
        _ request: P2PRelayRequest,
        from connection: NWConnection,
        sendData: @escaping (Data, NWConnection) -> Void
    ) async {
        // Validate domain
        guard let url = URL(string: request.url),
              let host = url.host,
              allowedDomains.contains(host) else {
            let response = P2PRelayResponse(
                id: request.id,
                statusCode: 403,
                headers: nil,
                body: nil,
                error: "Domain not allowed"
            )
            if let data = try? JSONEncoder().encode(response) {
                let envelope = P2PEnvelope(type: .relayResponse, payload: data)
                if let envelopeData = try? JSONEncoder().encode(envelope) {
                    sendData(envelopeData, connection)
                }
            }
            return
        }

        // Rate limit check
        guard checkRateLimit(clientId: request.clientId) else {
            let response = P2PRelayResponse(
                id: request.id,
                statusCode: 429,
                headers: nil,
                body: nil,
                error: "Rate limit exceeded"
            )
            if let data = try? JSONEncoder().encode(response) {
                let envelope = P2PEnvelope(type: .relayResponse, payload: data)
                if let envelopeData = try? JSONEncoder().encode(envelope) {
                    sendData(envelopeData, connection)
                }
            }
            return
        }

        // Execute HTTP request
        do {
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = request.method
            urlRequest.httpBody = request.body

            if let headers = request.headers {
                for (key, value) in headers {
                    urlRequest.setValue(value, forHTTPHeaderField: key)
                }
            }

            let (data, urlResponse) = try await session.data(for: urlRequest)

            let httpResponse = urlResponse as? HTTPURLResponse
            var responseHeaders: [String: String]?
            if let allHeaders = httpResponse?.allHeaderFields as? [String: String] {
                responseHeaders = allHeaders
            }

            let response = P2PRelayResponse(
                id: request.id,
                statusCode: httpResponse?.statusCode ?? 200,
                headers: responseHeaders,
                body: data,
                error: nil
            )

            if let responseData = try? JSONEncoder().encode(response) {
                let envelope = P2PEnvelope(type: .relayResponse, payload: responseData)
                if let envelopeData = try? JSONEncoder().encode(envelope) {
                    sendData(envelopeData, connection)
                }
            }
        } catch {
            let response = P2PRelayResponse(
                id: request.id,
                statusCode: 502,
                headers: nil,
                body: nil,
                error: error.localizedDescription
            )
            if let responseData = try? JSONEncoder().encode(response) {
                let envelope = P2PEnvelope(type: .relayResponse, payload: responseData)
                if let envelopeData = try? JSONEncoder().encode(envelope) {
                    sendData(envelopeData, connection)
                }
            }
        }
    }

    // MARK: - Rate Limiting

    private func checkRateLimit(clientId: String) -> Bool {
        let now = Date()

        if let record = clientRequestCounts[clientId] {
            if now.timeIntervalSince(record.windowStart) > 60 {
                // Reset window
                clientRequestCounts[clientId] = (count: 1, windowStart: now)
                return true
            } else if record.count >= maxRequestsPerMinute {
                return false
            } else {
                clientRequestCounts[clientId] = (count: record.count + 1, windowStart: record.windowStart)
                return true
            }
        } else {
            clientRequestCounts[clientId] = (count: 1, windowStart: now)
            return true
        }
    }
}
