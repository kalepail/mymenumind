import Foundation
import Testing
@testable import MyMenuMindCore

@Test func parsesTopLevelItemsArray() throws {
    let data = """
    {
      "items": [
        {
          "id": "a",
          "title": "Original article",
          "url": "https://example.com/article",
          "type": "bookmark",
          "created_at": "2026-05-08T18:35:00Z"
        }
      ]
    }
    """.data(using: .utf8)!

    let items = try MymindResponseParser.parseItems(from: data)

    #expect(items.count == 1)
    #expect(items[0].id == "a")
    #expect(items[0].title == "Original article")
    #expect(items[0].url?.absoluteString == "https://example.com/article")
    #expect(items[0].kind == "bookmark")
    #expect(items[0].createdAt != nil)
}

@Test func parsesMymindObjectSourceAndMarkdownContent() throws {
    let data = """
    {
      "items": [
        {
          "id": "abc123",
          "content": {
            "type": "text/markdown",
            "body": "A saved note"
          },
          "source": {
            "url": "https://source.example/page"
          },
          "bumped": "2026-05-08T18:35:00Z"
        }
      ]
    }
    """.data(using: .utf8)!

    let items = try MymindResponseParser.parseItems(from: data)

    #expect(items.count == 1)
    #expect(items[0].title == "A saved note")
    #expect(items[0].url?.absoluteString == "https://source.example/page")
    #expect(items[0].createdAt != nil)
}

@Test func prefersRawAssetThenSourceThenObjectURL() throws {
    let data = """
    {
      "items": [
        {
          "id": "asset1",
          "title": "Image",
          "url": "https://source.example/page",
          "blob": {
            "url": "https://cdn.example/raw.png"
          }
        },
        {
          "id": "source1",
          "title": "Article",
          "source": {
            "url": "https://source.example/article"
          }
        },
        {
          "id": "note1",
          "content": {
            "type": "text/markdown",
            "body": "Just a note"
          }
        }
      ]
    }
    """.data(using: .utf8)!

    let items = try MymindResponseParser.parseItems(
        from: data,
        objectURLTemplate: "https://access.mymind.test/objects/{id}"
    )

    #expect(items[0].preferredOpenURL?.absoluteString == "https://cdn.example/raw.png")
    #expect(items[1].preferredOpenURL?.absoluteString == "https://source.example/article")
    #expect(items[2].preferredOpenURL?.absoluteString == "https://access.mymind.test/objects/note1")
}

@Test func prefersBumpedTimestampForRecency() throws {
    let data = """
    {
      "items": [
        {
          "id": "abc123",
          "title": "Resaved",
          "created": "2026-05-01T10:00:00Z",
          "bumped": "2026-05-08T18:35:00Z"
        }
      ]
    }
    """.data(using: .utf8)!

    let items = try MymindResponseParser.parseItems(from: data)

    #expect(items[0].createdAt == ISO8601DateFormatter().date(from: "2026-05-08T18:35:00Z"))
}

@Test func parsesNestedDataResults() throws {
    let data = """
    {
      "data": {
        "results": [
          {
            "_id": 42,
            "content": "Remember this idea",
            "source": {
              "href": "https://example.com/source"
            }
          }
        ]
      }
    }
    """.data(using: .utf8)!

    let items = try MymindResponseParser.parseItems(from: data)

    #expect(items.count == 1)
    #expect(items[0].id == "42")
    #expect(items[0].title == "Remember this idea")
    #expect(items[0].url?.absoluteString == "https://example.com/source")
}

@Test func returnsEmptyArrayForUnknownShape() throws {
    let data = #"{"ok": true}"#.data(using: .utf8)!

    let items = try MymindResponseParser.parseItems(from: data)

    #expect(items.isEmpty)
}
