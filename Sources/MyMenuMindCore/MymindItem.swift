import Foundation

public struct MymindItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var url: URL?
    public var rawAssetURL: URL?
    public var sourceURL: URL?
    public var objectURL: URL?
    public var kind: String?
    public var createdAt: Date?

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        url: URL? = nil,
        rawAssetURL: URL? = nil,
        sourceURL: URL? = nil,
        objectURL: URL? = nil,
        kind: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.url = url
        self.rawAssetURL = rawAssetURL
        self.sourceURL = sourceURL
        self.objectURL = objectURL
        self.kind = kind
        self.createdAt = createdAt
    }

    public var preferredOpenURL: URL? {
        rawAssetURL ?? sourceURL ?? url ?? objectURL
    }
}
