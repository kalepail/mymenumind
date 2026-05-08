import Foundation

public enum MymindResponseParser {
    public static func parseItems(from data: Data, objectURLTemplate: String? = nil) throws -> [MymindItem] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionaries = firstItemArray(in: object) else {
            return []
        }

        return dictionaries.enumerated().map { index, dictionary in
            item(from: dictionary, fallbackID: String(index), objectURLTemplate: objectURLTemplate)
        }
    }

    private static func firstItemArray(in object: Any) -> [[String: Any]]? {
        if let array = object as? [[String: Any]] {
            return array
        }

        guard let dictionary = object as? [String: Any] else {
            return nil
        }

        for key in ["items", "data", "results", "cards"] {
            if let array = dictionary[key] as? [[String: Any]] {
                return array
            }

            if let nested = dictionary[key] as? [String: Any],
               let array = firstItemArray(in: nested) {
                return array
            }
        }

        return nil
    }

    private static func item(from dictionary: [String: Any], fallbackID: String, objectURLTemplate: String?) -> MymindItem {
        let nestedSource = dictionary["source"] as? [String: Any]
        let nestedMetadata = dictionary["metadata"] as? [String: Any]
        let nestedContent = dictionary["content"] as? [String: Any]
        let nestedBlob = dictionary["blob"] as? [String: Any]
        let nestedScreenshot = dictionary["screenshot"] as? [String: Any]

        let id = stringValue(in: dictionary, keys: ["id", "_id", "uuid", "card_id"]) ?? fallbackID
        let title = firstNonEmpty([
            stringValue(in: dictionary, keys: ["title", "name", "headline"]),
            stringValue(in: dictionary, keys: ["text", "content", "note"]),
            nestedContent.flatMap { stringValue(in: $0, keys: ["body"]) },
            nestedMetadata.flatMap { stringValue(in: $0, keys: ["title", "name"]) },
            nestedSource.flatMap { stringValue(in: $0, keys: ["title", "name"]) }
        ]) ?? "Untitled"

        let subtitle = firstNonEmpty([
            stringValue(in: dictionary, keys: ["description", "summary", "excerpt"]),
            nestedMetadata.flatMap { stringValue(in: $0, keys: ["description", "summary"]) }
        ])

        let urlString = firstNonEmpty([
            stringValue(in: dictionary, keys: ["url", "href", "link", "permalink", "source_url", "sourceUrl", "sourceURL", "original_url", "originalUrl", "originalURL", "external_url", "externalUrl", "actual_url", "actualUrl"]),
            nestedSource.flatMap { stringValue(in: $0, keys: ["url", "href", "link", "original_url", "originalUrl", "originalURL", "source_url", "sourceUrl", "sourceURL"]) },
            nestedMetadata.flatMap { stringValue(in: $0, keys: ["url", "href", "link", "original_url", "originalUrl", "source_url", "sourceUrl"]) }
        ])
        let sourceURLString = firstNonEmpty([
            nestedSource.flatMap { stringValue(in: $0, keys: ["url", "href", "link", "original_url", "originalUrl", "originalURL", "source_url", "sourceUrl", "sourceURL"]) },
            stringValue(in: dictionary, keys: ["url", "source_url", "sourceUrl", "sourceURL", "original_url", "originalUrl", "originalURL"])
        ])
        let rawAssetURLString = firstNonEmpty([
            nestedBlob.flatMap { stringValue(in: $0, keys: ["url", "href", "link"]) },
            nestedScreenshot.flatMap { stringValue(in: $0, keys: ["url", "href", "link"]) }
        ])
        let objectURLString = objectURLTemplate?.replacingOccurrences(of: "{id}", with: id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)

        return MymindItem(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: subtitle,
            url: urlString.flatMap(URL.init(string:)),
            rawAssetURL: rawAssetURLString.flatMap(URL.init(string:)),
            sourceURL: sourceURLString.flatMap(URL.init(string:)),
            objectURL: objectURLString.flatMap(URL.init(string:)),
            kind: stringValue(in: dictionary, keys: ["type", "kind", "card_type"]),
            createdAt: parseDate(stringValue(in: dictionary, keys: ["bumped", "modified", "createdAt", "created_at", "created", "date"]))
        )
    }

    private static func stringValue(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = dictionary[key] else {
                continue
            }

            if let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return string
            }

            if let int = value as? Int {
                return String(int)
            }

            if let double = value as? Double {
                return String(double)
            }
        }

        return nil
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        return isoFormatter.date(from: value)
    }
}
