import Foundation

public struct APIConfiguration: Codable, Equatable, Sendable {
    public var baseURLString: String
    public var keyID: String
    public var secret: String
    public var userAgent: String
    public var apiVersion: String
    public var objectURLTemplate: String

    public init(
        baseURLString: String = "https://api.mymind.com",
        keyID: String = "",
        secret: String = "",
        userAgent: String = "MyMenuMind/0.1.0",
        apiVersion: String = "0.1",
        objectURLTemplate: String = "https://access.mymind.com/objects/{id}"
    ) {
        self.baseURLString = baseURLString
        self.keyID = keyID
        self.secret = secret
        self.userAgent = userAgent
        self.apiVersion = apiVersion
        self.objectURLTemplate = objectURLTemplate
    }

    private enum CodingKeys: String, CodingKey {
        case baseURLString
        case keyID
        case secret
        case userAgent
        case apiVersion
        case objectURLTemplate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURLString = try container.decodeIfPresent(String.self, forKey: .baseURLString) ?? "https://api.mymind.com"
        keyID = try container.decodeIfPresent(String.self, forKey: .keyID) ?? ""
        secret = try container.decodeIfPresent(String.self, forKey: .secret) ?? ""
        userAgent = try container.decodeIfPresent(String.self, forKey: .userAgent) ?? "MyMenuMind/0.1.0"
        apiVersion = try container.decodeIfPresent(String.self, forKey: .apiVersion) ?? "0.1"
        objectURLTemplate = try container.decodeIfPresent(String.self, forKey: .objectURLTemplate) ?? "https://access.mymind.com/objects/{id}"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseURLString, forKey: .baseURLString)
        try container.encode("", forKey: .keyID)
        try container.encode("", forKey: .secret)
        try container.encode(userAgent, forKey: .userAgent)
        try container.encode(apiVersion, forKey: .apiVersion)
        try container.encode(objectURLTemplate, forKey: .objectURLTemplate)
    }
}
