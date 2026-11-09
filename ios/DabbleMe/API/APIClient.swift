import Foundation

enum APIError: LocalizedError, Equatable {
    /// No usable tokens: the user must sign in again.
    case signedOut
    case server(status: Int, code: String, message: String)
    case network(String)
    case decoding

    var code: String? {
        if case .server(_, let code, _) = self { return code }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .signedOut: "Your session ended. Please sign in again."
        case .server(_, _, let message): message
        case .network(let message): message
        case .decoding: "Something unexpected came back from Dabble Me."
        }
    }
}

/// Thin client for /api/v1. Retries once after a token refresh on 401.
struct APIClient: Sendable {
    let tokens: TokenProvider
    var session: URLSession = .shared

    func get<T: Decodable & Sendable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try decode(await send("GET", path, query: query, body: nil))
    }

    func post<T: Decodable & Sendable>(_ path: String, _ body: some Encodable & Sendable) async throws -> T {
        try decode(await send("POST", path, body: try encode(body)))
    }

    func patch<T: Decodable & Sendable>(_ path: String, _ body: some Encodable & Sendable) async throws -> T {
        try decode(await send("PATCH", path, body: try encode(body)))
    }

    func delete(_ path: String) async throws {
        _ = try await send("DELETE", path, body: nil)
    }

    /// PUTs photo bytes straight to the presigned S3 URL from /api/v1/image_uploads.
    func upload(_ data: Data, to target: ImageUpload) async throws {
        var request = URLRequest(url: target.uploadUrl)
        request.httpMethod = target.uploadMethod
        target.uploadHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.timeoutInterval = 120
        let response: URLResponse
        do {
            (_, response) = try await session.upload(for: request, from: data)
        } catch {
            throw APIError.network("The photo didn't upload. Check your connection and try again.")
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.network("The photo didn't upload. Please try again.")
        }
    }

    // MARK: - Plumbing

    private func send(_ method: String, _ path: String, query: [String: String] = [:], body: Data?, retrying: Bool = false) async throws -> Data {
        var components = URLComponents(url: AppConfig.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(try await tokens.accessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        #if DEBUG
        // UI tests: -DabbleDebugSlowWrites <ms> slows saves like a poor connection, so quick
        // changes overlap requests still in flight.
        let slowWrites = UserDefaults.standard.integer(forKey: "DabbleDebugSlowWrites")
        if slowWrites > 0, method != "GET" { try await Task.sleep(for: .milliseconds(slowWrites)) }
        #endif

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.network("Couldn't reach Dabble Me. Check your connection and try again.")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            guard !retrying else { throw APIError.signedOut }
            _ = try await tokens.refresh()
            return try await send(method, path, query: query, body: body, retrying: true)
        }
        guard (200..<300).contains(status) else {
            let body = try? Self.decoder.decode(APIErrorBody.self, from: data)
            let message = body?.details?.first ?? body?.message ?? "Something went wrong (\(status))."
            throw APIError.server(status: status, code: body?.error ?? "http_\(status)", message: message)
        }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    private func encode(_ body: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(body)
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
