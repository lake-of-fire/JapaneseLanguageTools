# JapaneseLanguageTools

Japanese text classification, pronunciation and audio helpers used by Manabi Reader.

## Requirements

The current dependency graph requires **Swift 6.4 or later**, including Swift Sharing 2.10.1 and xctest-dynamic-overlay 1.13.1. The manifest retains Swift 5 language mode; its tools-version line describes the manifest API baseline, not the minimum compiler of the complete dependency graph.

The declared deployment minimums are macOS 15, iOS 15 and watchOS 9. watchOS 9 matches the minimum required by Sharing and the overlay bridge. A deployment declaration is not evidence that each platform has been built or tested.

SQLiteData stays at 1.8.2 and StructuredQueries at 0.34.0 to retain iOS 15 compatibility. The overlay bridge forwards the legacy IssueReporting products to swift-issue-reporting, avoiding duplicate module targets when composing the graph with Sharing.

Run the maintained XCTest suite with `swift test`. The latest qualification covers native macOS Debug; iOS, watchOS and Release qualification remain separate.
