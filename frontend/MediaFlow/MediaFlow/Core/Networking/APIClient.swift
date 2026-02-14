import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case httpError(Int, String)
    case decodingError(Error)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .decodingError(let err): return "Decoding error: \(err.localizedDescription)"
        case .unknown: return "Unknown error"
        }
    }
}

class APIClient {
    static var defaultBaseURL: String = "http://localhost:9876"

    let baseURL: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: String? = nil) {
        let resolvedURL = baseURL ?? Self.defaultBaseURL
        self.baseURL = resolvedURL
        self.session = URLSession.shared

        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601

        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        let url = try buildURL(path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        return try await execute(request)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let url = try buildURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)
        return try await execute(request)
    }

    func post<T: Decodable>(_ path: String) async throws -> T {
        let url = try buildURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        return try await execute(request)
    }

    func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let url = try buildURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)
        return try await execute(request)
    }

    func patch<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let url = try buildURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)
        return try await execute(request)
    }

    func delete(_ path: String) async throws {
        let url = try buildURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.unknown }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode, "Delete failed")
        }
    }

    func getRaw(_ path: String, queryItems: [URLQueryItem]? = nil) async throws -> Data {
        let url = try buildURL(path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.unknown }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func buildURL(_ path: String, queryItems: [URLQueryItem]? = nil) throws -> URL {
        guard var components = URLComponents(string: baseURL + path) else {
            throw APIError.invalidURL
        }
        if let queryItems = queryItems, !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw APIError.unknown }
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw APIError.httpError(httpResponse.statusCode, body)
            }
            return try decoder.decode(T.self, from: data)
        } catch let error as APIError {
            throw error
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }
}
