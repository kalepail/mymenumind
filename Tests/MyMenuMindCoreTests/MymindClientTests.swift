import Foundation
import Testing
@testable import MyMenuMindCore

@Suite(.serialized)
struct MymindClientTests {
    @Test func buildsRelativeURLsFromConfiguredBaseURL() throws {
        let client = MymindClient(
            configuration: APIConfiguration(
                baseURLString: "https://api.mymind.com",
                keyID: "key",
                secret: "MTIzNDU2Nzg5MDEyMzQ1Ng=="
            )
        )

        let url = try client.makeURL(path: "/objects", queryItems: [
            URLQueryItem(name: "id", value: "abc"),
            URLQueryItem(name: "contentAs", value: "text/markdown")
        ])

        #expect(url.absoluteString == "https://api.mymind.com/objects?id=abc&contentAs=text/markdown")
    }

    @Test func rejectsInsecureBaseURLBeforeSendingCredentials() async {
        let client = MymindClient(configuration: APIConfiguration(
            baseURLString: "http://api.mymind.test",
            keyID: "kid_123",
            secret: "MTIzNDU2Nzg5MDEyMzQ1Ng=="
        ))

        do {
            _ = try await client.recent()
            Issue.record("Expected insecure base URL error")
        } catch let error as MymindClientError {
            #expect(error == .insecureBaseURL("http://api.mymind.test"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func encodedConfigurationDoesNotPersistCredentials() throws {
        let configuration = APIConfiguration(
            keyID: "kid_123",
            secret: "MTIzNDU2Nzg5MDEyMzQ1Ng=="
        )

        let data = try JSONEncoder().encode(configuration)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["keyID"] as? String == "")
        #expect(object["secret"] as? String == "")
    }

    @Test func rejectsMissingCredentialsBeforeNetworkRequest() async {
        let client = MymindClient(configuration: APIConfiguration(keyID: "", secret: ""))

        do {
            _ = try await client.recent()
            Issue.record("Expected missing credentials error")
        } catch let error as MymindClientError {
            #expect(error == .missingCredentials)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func signedJWTContainsConfiguredKeyAndBoundMethodPath() throws {
        let issuedAt = Date(timeIntervalSince1970: 1_777_000_000)
        let client = MymindClient(configuration: APIConfiguration(
            keyID: "kid_123",
            secret: "MTIzNDU2Nzg5MDEyMzQ1Ng=="
        ))

        let token = try client.signedJWT(method: "GET", path: "/objects", issuedAt: issuedAt)
        let segments = token.split(separator: ".").map(String.init)

        #expect(segments.count == 3)
        let header = try decodeSegment(segments[0])
        let claims = try decodeSegment(segments[1])
        #expect(header["alg"] as? String == "HS256")
        #expect(header["kid"] as? String == "kid_123")
        #expect(claims["method"] as? String == "GET")
        #expect(claims["path"] as? String == "/objects")
        #expect(claims["iat"] as? Int == 1_777_000_000)
        #expect(claims["exp"] as? Int == 1_777_000_300)
    }

    @Test func searchCallsSearchThenFetchesMatchedObjects() async throws {
        let requests = RequestRecorder()
        MockURLProtocol.requestHandler = { request in
            requests.append(request)

            switch request.url?.path {
            case "/search":
                #expect(request.httpMethod == "GET")
                #expect(request.value(forHTTPHeaderField: "User-Agent") == "MyMenuMindTests/1")
                #expect(request.value(forHTTPHeaderField: "API-Version") == "0.1")
                #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
                #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "q", value: "design notes")) == true)
                return httpResponse(for: request, body: #"{"matches":[{"id":"b","score":9},{"id":"a","score":7}]}"#)
            case "/objects":
                let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
                #expect(queryItems.filter { $0.name == "id" }.map(\.value) == ["b", "a"])
                return httpResponse(for: request, body: #"{"items":[{"id":"a","title":"A","source":{"url":"https://a.example"}},{"id":"b","title":"B","source":{"url":"https://b.example"}}]}"#)
            default:
                Issue.record("Unexpected request: \(request.url?.absoluteString ?? "nil")")
                return httpResponse(for: request, statusCode: 404, body: #"{"detail":"not found"}"#)
            }
        }

        let client = MymindClient(
            configuration: testConfiguration,
            session: mockSession,
            dateProvider: { Date(timeIntervalSince1970: 1_777_000_000) }
        )

        let items = try await client.search(query: "design notes", limit: 2)

        #expect(requests.urls.map(\.path) == ["/search", "/objects"])
        #expect(items.map(\.id) == ["b", "a"])
        #expect(items[0].url?.absoluteString == "https://b.example")
    }

    @Test func recentSortsObjectsByBumpedTimestampDescending() async throws {
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/objects")
            let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(queryItems.contains(URLQueryItem(name: "limit", value: "3")))
            return httpResponse(for: request, body: """
            [
              {
                "id": "older",
                "title": "Older",
                "bumped": "2026-05-08T10:00:00Z"
              },
              {
                "id": "newer",
                "title": "Newer",
                "bumped": "2026-05-08T12:00:00Z"
              },
              {
                "id": "middle",
                "title": "Middle",
                "modified": "2026-05-08T11:00:00Z"
              }
            ]
            """)
        }

        let client = MymindClient(configuration: testConfiguration, session: mockSession)

        let items = try await client.recent(limit: 3)

        #expect(items.map(\.id) == ["newer", "middle", "older"])
    }

    @Test func recentPreservesAPIOrderWhenTimestampsTieOrAreMissing() async throws {
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/objects")
            return httpResponse(for: request, body: """
            [
              { "id": "first", "title": "First" },
              { "id": "second", "title": "Second" },
              {
                "id": "third",
                "title": "Third",
                "bumped": "2026-05-08T10:00:00Z"
              },
              {
                "id": "fourth",
                "title": "Fourth",
                "bumped": "2026-05-08T10:00:00Z"
              }
            ]
            """)
        }

        let client = MymindClient(configuration: testConfiguration, session: mockSession)

        let items = try await client.recent(limit: 4)

        #expect(items.map(\.id) == ["third", "fourth", "first", "second"])
    }

    @Test func exposesRateLimitRetryAfterHeader() async throws {
        MockURLProtocol.requestHandler = { request in
            httpResponse(
                for: request,
                statusCode: 429,
                body: #"{"detail":"rate limited"}"#,
                headerFields: ["Retry-After": "12"]
            )
        }

        let client = MymindClient(configuration: testConfiguration, session: mockSession)

        do {
            _ = try await client.recent()
            Issue.record("Expected rate limit error")
        } catch let error as MymindClientError {
            #expect(error == .rateLimited(retryAfter: 12))
        }
    }

    @Test func exposesForbiddenAsPermissionMessage() async throws {
        MockURLProtocol.requestHandler = { request in
            httpResponse(for: request, statusCode: 403, body: "Forbidden")
        }

        let client = MymindClient(configuration: testConfiguration, session: mockSession)

        do {
            try await client.createQuickNote(text: "Remember this")
            Issue.record("Expected forbidden error")
        } catch let error as MymindClientError {
            #expect(error == .forbidden(
                message: "mymind denied this. Check the key's access level; quick notes require Full access."
            ))
            #expect(error.localizedDescription == "mymind denied this. Check the key's access level; quick notes require Full access.")
        }
    }

    @Test func quickNoteCreatesMarkdownContentObject() async throws {
        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/objects")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

            let body = try #require(requestBodyData(from: request))
            let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let content = try #require(object["content"] as? [String: Any])
            #expect(content["type"] as? String == "text/markdown")
            #expect(content["body"] as? String == "Remember this")

            return httpResponse(for: request, statusCode: 201, body: #"{"id":"note"}"#)
        }

        let client = MymindClient(configuration: testConfiguration, session: mockSession)

        try await client.createQuickNote(text: "Remember this")
    }
}

private let testConfiguration = APIConfiguration(
    baseURLString: "https://api.mymind.test",
    keyID: "kid_123",
    secret: "MTIzNDU2Nzg5MDEyMzQ1Ng==",
    userAgent: "MyMenuMindTests/1",
    objectURLTemplate: "https://access.mymind.test/objects/{id}"
)

private var mockSession: URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func httpResponse(
    for request: URLRequest,
    statusCode: Int = 200,
    body: String,
    headerFields: [String: String] = [:]
) -> (HTTPURLResponse, Data) {
    var headers = ["Content-Type": "application/json"]
    headers.merge(headerFields) { _, new in new }
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: headers
    )!
    return (response, Data(body.utf8))
}

private func decodeSegment(_ segment: String) throws -> [String: Any] {
    var base64 = segment
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")

    while base64.count % 4 != 0 {
        base64.append("=")
    }

    let data = try #require(Data(base64Encoded: base64))
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func requestBodyData(from request: URLRequest) -> Data? {
    if let httpBody = request.httpBody {
        return httpBody
    }

    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
        let count = stream.read(buffer, maxLength: bufferSize)
        if count <= 0 {
            break
        }
        data.append(buffer, count: count)
    }

    return data
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    var urls: [URL] {
        lock.withLock {
            requests.compactMap(\.url)
        }
    }

    func append(_ request: URLRequest) {
        lock.withLock {
            requests.append(request)
        }
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: MymindClientError.invalidResponse)
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
