import CryptoKit
import Foundation

public enum MymindClientError: LocalizedError, Equatable {
    case invalidBaseURL(String)
    case insecureBaseURL(String)
    case missingCredentials
    case invalidSecret
    case invalidResponse
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let value):
            return "Invalid base URL: \(value)"
        case .insecureBaseURL(let value):
            return "The mymind API base URL must use HTTPS: \(value)"
        case .missingCredentials:
            return "Add your mymind access key ID and secret in Settings."
        case .invalidSecret:
            return "The mymind access key secret must be base64 encoded."
        case .invalidResponse:
            return "mymind returned an unexpected response."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "mymind rate limited this request. Try again in \(Int(ceil(retryAfter))) seconds."
            }
            return "mymind rate limited this request. Try again shortly."
        case .serverError(let statusCode, let message):
            return "mymind returned HTTP \(statusCode): \(message)"
        }
    }
}

public final class MymindClient: Sendable {
    private struct SearchResponse: Decodable {
        var matches: [SearchMatch]
    }

    private struct SearchMatch: Decodable {
        var id: String
    }

    private let configuration: APIConfiguration
    private let session: URLSession
    private let dateProvider: @Sendable () -> Date

    public init(
        configuration: APIConfiguration,
        session: URLSession = .shared,
        dateProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.session = session
        self.dateProvider = dateProvider
    }

    public func search(query: String, limit: Int = 20) async throws -> [MymindItem] {
        let searchData = try await data(for: request(
            path: "/search",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit))
            ],
            method: "GET"
        ))

        let matches = try JSONDecoder().decode(SearchResponse.self, from: searchData).matches
        guard !matches.isEmpty else {
            return []
        }

        return try await objects(ids: matches.map(\.id), limit: limit)
    }

    public func recent(limit: Int = 10) async throws -> [MymindItem] {
        let data = try await data(for: request(
            path: "/objects",
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "contentAs", value: "text/markdown")
            ],
            method: "GET"
        ))
        return try MymindResponseParser.parseItems(from: data, objectURLTemplate: configuration.objectURLTemplate)
            .enumerated()
            .sorted { lhs, rhs in
                let lhsDate = lhs.element.createdAt
                let rhsDate = rhs.element.createdAt
                if lhsDate == rhsDate {
                    return lhs.offset < rhs.offset
                }
                return (lhsDate ?? .distantPast) > (rhsDate ?? .distantPast)
            }
            .map(\.element)
    }

    public func createQuickNote(text: String) async throws {
        let payload: [String: Any] = [
            "content": [
                "type": "text/markdown",
                "body": text
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await data(for: request(path: "/objects", method: "POST", body: body))
    }

    public func makeURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard let baseURL = URL(string: configuration.baseURLString),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw MymindClientError.invalidBaseURL(configuration.baseURLString)
        }

        // The signed JWT authorizes this exact request, so do not allow users to
        // accidentally send it over plaintext transport.
        guard components.scheme?.lowercased() == "https" else {
            throw MymindClientError.insecureBaseURL(configuration.baseURLString)
        }

        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw MymindClientError.invalidBaseURL(configuration.baseURLString)
        }

        return url
    }

    public func signedJWT(method: String, path: String, issuedAt: Date) throws -> String {
        let keyID = configuration.keyID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = configuration.secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyID.isEmpty, !secret.isEmpty else {
            throw MymindClientError.missingCredentials
        }

        guard let secretData = Data(base64Encoded: secret) else {
            throw MymindClientError.invalidSecret
        }

        let issuedAtSeconds = Int(issuedAt.timeIntervalSince1970)
        let header: [String: Any] = [
            "alg": "HS256",
            "kid": keyID
        ]
        let claims: [String: Any] = [
            "method": method.uppercased(),
            "path": path,
            "iat": issuedAtSeconds,
            "exp": issuedAtSeconds + 300
        ]

        let headerSegment = try JSONSerialization.data(withJSONObject: header).base64URLEncodedString()
        let claimsSegment = try JSONSerialization.data(withJSONObject: claims).base64URLEncodedString()
        let signingInput = "\(headerSegment).\(claimsSegment)"
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(signingInput.utf8),
            using: SymmetricKey(data: secretData)
        )

        return "\(signingInput).\(Data(signature).base64URLEncodedString())"
    }

    private func objects(ids: [String], limit: Int) async throws -> [MymindItem] {
        var queryItems = ids.map { URLQueryItem(name: "id", value: $0) }
        queryItems.append(URLQueryItem(name: "contentAs", value: "text/markdown"))
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))

        let data = try await data(for: request(path: "/objects", queryItems: queryItems, method: "GET"))
        let items = try MymindResponseParser.parseItems(from: data, objectURLTemplate: configuration.objectURLTemplate)
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })

        return items.sorted {
            (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max)
        }
    }

    private func request(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        body: Data? = nil
    ) throws -> URLRequest {
        let token = try signedJWT(method: method, path: path, issuedAt: dateProvider())

        var request = URLRequest(url: try makeURL(path: path, queryItems: queryItems))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        if !configuration.apiVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(configuration.apiVersion, forHTTPHeaderField: "API-Version")
        }

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MymindClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 429 {
                throw MymindClientError.rateLimited(retryAfter: retryAfter(from: httpResponse))
            }
            let message = problemDetail(from: data) ?? String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw MymindClientError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        return data
    }

    private func problemDetail(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return object["detail"] as? String ?? object["type"] as? String
    }

    private func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        if let seconds = TimeInterval(value) {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"

        guard let date = formatter.date(from: value) else {
            return nil
        }
        return max(0, date.timeIntervalSince(dateProvider()))
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
