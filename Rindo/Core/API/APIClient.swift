import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case serverNotConfigured
    case httpError(statusCode: Int)
    case noData
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "無効なURLです"
        case .serverNotConfigured:
            return "バックエンドサーバの URL が設定されていません"
        case .httpError(let code):
            return "サーバエラー（\(code)）"
        case .noData:
            return "データがありません"
        case .unauthorized:
            return "認証が必要です"
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private var token: String?

    private var baseURL: URL? { AppConfig.backendServerURL }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    func setToken(_ token: String?) {
        self.token = token
    }

    // MARK: - GET

    /// Raw data fetch — useful for passing GeoJSON directly to MapLibre
    func fetchData(path: String, baseURL override: URL? = nil) async throws -> Data {
        guard let base = override ?? baseURL else {
            throw APIError.serverNotConfigured
        }
        guard let url = URL(string: path, relativeTo: base) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        applyAuth(&request)
        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        return data
    }

    /// Typed JSON fetch
    func fetch<T: Decodable & Sendable>(_ type: T.Type, path: String) async throws -> T {
        let data = try await fetchData(path: path)
        return try decode(T.self, from: data)
    }

    // MARK: - POST

    /// POST with JSON body, returning decoded response
    func post<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        body: (any Encodable & Sendable)? = nil,
        baseURL override: URL? = nil
    ) async throws -> T {
        guard let base = override ?? baseURL else {
            throw APIError.serverNotConfigured
        }
        guard let url = URL(string: path, relativeTo: base) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&request)
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        } else {
            request.httpBody = Data("{}".utf8)
        }
        let (data, response) = try await session.data(for: request)
        try checkResponse(response)
        return try decode(T.self, from: data)
    }

    /// POST with no meaningful response body (fire-and-forget)
    func postIgnoringResponse(path: String) async throws {
        guard let base = baseURL else {
            throw APIError.serverNotConfigured
        }
        guard let url = URL(string: path, relativeTo: base) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyAuth(&request)
        let (_, response) = try await session.data(for: request)
        try checkResponse(response)
    }

    // MARK: - Helpers

    private func applyAuth(_ request: inout URLRequest) {
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func checkResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.noData
        }
        if http.statusCode == 401 {
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}
