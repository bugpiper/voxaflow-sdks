import Foundation

/// REST client: attaches the token, parses JSON, and on a 401 transparently refreshes the
/// token (via onTokenRefresh) and retries once.
final class VoxaRest {
    private let endpoint: String
    private var token: String
    private let onTokenRefresh: (() async throws -> String)?
    var onTokenChanged: ((String) -> Void)?
    private let session = URLSession.shared

    init(endpoint: String, token: String, onTokenRefresh: (() async throws -> String)?) {
        self.endpoint = endpoint
        self.token = token
        self.onTokenRefresh = onTokenRefresh
    }

    @discardableResult
    func post(_ path: String, _ body: [String: Any]? = nil) async throws -> [String: Any] {
        try await send("POST", path, body)
    }
    @discardableResult
    func get(_ path: String) async throws -> [String: Any] { try await send("GET", path, nil) }
    @discardableResult
    func put(_ path: String, _ body: [String: Any]? = nil) async throws -> [String: Any] {
        try await send("PUT", path, body)
    }
    @discardableResult
    func delete(_ path: String, _ body: [String: Any]? = nil) async throws -> [String: Any] {
        try await send("DELETE", path, body)
    }

    private func send(_ method: String, _ path: String, _ body: [String: Any]?, retry: Bool = true) async throws -> [String: Any] {
        guard let url = URL(string: endpoint + path) else {
            throw VoxaError(.connection, "Invalid URL for \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw VoxaError(.connection, "Network error calling \(path)")
        }
        guard let http = resp as? HTTPURLResponse else {
            throw VoxaError(.connection, "No HTTP response for \(path)")
        }

        if http.statusCode == 401, retry, let onTokenRefresh {
            do {
                token = try await onTokenRefresh()
                onTokenChanged?(token)
            } catch {
                throw VoxaError(.auth, "Token refresh failed", status: 401)
            }
            return try await send(method, path, body, retry: false)
        }

        if (200..<300).contains(http.statusCode) {
            if data.isEmpty { return [:] }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }
        let code: VoxaErrorCode = (http.statusCode == 401 || http.statusCode == 403) ? .auth : .server
        throw VoxaError(code, errorMessage(data, http.statusCode), status: http.statusCode)
    }

    private func errorMessage(_ data: Data, _ status: Int) -> String {
        if let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let m = j["message"] as? String { return m }
            if let e = j["error"] as? String { return e }
        }
        return "Request failed (HTTP \(status))"
    }
}
