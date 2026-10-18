import Foundation
import XCTest
@testable import JapaneseLanguageTools

final class JapanesePronunciationAudioCacheTests: XCTestCase {
    private let sourceURL = URL(string: "https://manabi.io/media/audio/tofugu/pronunciation.mp3")!

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func makeCache(_ root: URL) -> JapanesePronunciationAudioCache {
        JapanesePronunciationAudioCache(directory: root) { url in
            // Cache ownership tests use fixture bytes; native MP3 admission is a separate contract.
            guard try Data(contentsOf: url) == Data("valid fixture".utf8) else {
                throw URLError(.cannotDecodeContentData)
            }
        }
    }

    private func makeInput(_ root: URL, valid: Bool = true) throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString + ".input")
        try Data((valid ? "valid fixture" : "corrupt").utf8).write(to: url)
        return url
    }

    private func key(_ expression: String = "猫", _ reading: String = "ねこ") throws
        -> JapanesePronunciationAudioCache.Key {
        try JapanesePronunciationAudioCache.Key(
            expression: expression, readingKana: reading, sourceURL: sourceURL
        )
    }

    func test_hostileAndDelimiterCollidingKeys_remainDistinctAndContained() async throws {
        let root = try makeRoot().resolvingSymlinksInPath().standardizedFileURL
        let cache = makeCache(root)
        let input = try makeInput(root)
        let keys = [try key("../../outside", "../reading"), try key("a【b", "c"), try key("a", "b【c")]
        var urls = Set<URL>()
        for key in keys {
            let artifact = try await cache.install(from: input, for: key)
            XCTAssertEqual(artifact.url.deletingLastPathComponent(), root)
            XCTAssertEqual(artifact.url.pathExtension, "mp3")
            urls.insert(artifact.url)
        }
        XCTAssertEqual(urls.count, keys.count)
        XCTAssertThrowsError(try key(String(repeating: "a", count: 4_097)))
    }

    func test_reopenedCache_revalidatesHitAndRejectsCorruptOrMissingBytes() async throws {
        let root = try makeRoot()
        let cache = makeCache(root)
        let key = try key()
        let artifact = try await cache.install(from: makeInput(root), for: key)
        let reopened = makeCache(root)
        let hit = try await reopened.cachedArtifact(for: key)
        XCTAssertEqual(hit?.url, artifact.url)
        try Data("corrupt".utf8).write(to: artifact.url)
        let corrupt = try await reopened.cachedArtifact(for: key)
        XCTAssertNil(corrupt)
        try FileManager.default.removeItem(at: artifact.url)
        let missing = try await reopened.cachedArtifact(for: key)
        XCTAssertNil(missing)
    }

    func test_oldFailure_doesNotEvictSuccessorFromAnotherCacheInstance() async throws {
        let root = try makeRoot()
        let firstCache = makeCache(root)
        let secondCache = makeCache(root)
        let key = try key()
        let input = try makeInput(root)
        let first = try await firstCache.install(from: input, for: key)
        let successor = try await secondCache.install(from: input, for: key)
        XCTAssertNotEqual(first.url, successor.url)
        try await firstCache.evict(first)
        let current = try await secondCache.cachedArtifact(for: key)
        XCTAssertEqual(current?.url, successor.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertEqual(try Data(contentsOf: successor.url), Data("valid fixture".utf8))
    }

    func test_replacedArtifact_staleReceiptCannotDeleteReplacement() async throws {
        let root = try makeRoot()
        let cache = makeCache(root)
        let key = try key()
        let artifact = try await cache.install(from: makeInput(root), for: key)
        let retired = root.appendingPathComponent("retired.mp3")
        try FileManager.default.moveItem(at: artifact.url, to: retired)
        try Data("valid fixture".utf8).write(to: artifact.url)
        try await cache.evict(artifact)
        let current = try await cache.cachedArtifact(for: key)
        XCTAssertEqual(current?.url, artifact.url)
    }

    func test_failedValidation_preservesPublishedManifestAndCleansStaging() async throws {
        let root = try makeRoot()
        let cache = makeCache(root)
        let key = try key()
        let artifact = try await cache.install(from: makeInput(root), for: key)
        do {
            _ = try await cache.install(from: makeInput(root, valid: false), for: key)
            XCTFail("Corrupt fixture must reject installation")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .cannotDecodeContentData)
        }
        let current = try await cache.cachedArtifact(for: key)
        XCTAssertEqual(current?.url, artifact.url)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.contains { $0.lastPathComponent.hasSuffix(".staging.mp3") })
    }

    func test_competingInstallers_publishOnlyCompleteOwnedArtifacts() async throws {
        let root = try makeRoot()
        let firstCache = makeCache(root)
        let secondCache = makeCache(root)
        let key = try key()
        let input = try makeInput(root)
        async let firstInstallation = firstCache.install(from: input, for: key)
        async let secondInstallation = secondCache.install(from: input, for: key)
        let (first, second) = try await (firstInstallation, secondInstallation)
        XCTAssertNotEqual(first.url, second.url)
        XCTAssertEqual(try Data(contentsOf: first.url), Data("valid fixture".utf8))
        XCTAssertEqual(try Data(contentsOf: second.url), Data("valid fixture".utf8))
        let current = try await firstCache.cachedArtifact(for: key)
        XCTAssertTrue(current?.url == first.url || current?.url == second.url)
    }

    func test_symbolicLinkArtifact_isNeverAValidHitOrEvictionTarget() async throws {
        let root = try makeRoot()
        let cache = makeCache(root)
        let key = try key()
        let artifact = try await cache.install(from: makeInput(root), for: key)
        let target = try makeInput(root)
        try FileManager.default.removeItem(at: artifact.url)
        try FileManager.default.createSymbolicLink(at: artifact.url, withDestinationURL: target)
        let hit = try await cache.cachedArtifact(for: key)
        XCTAssertNil(hit)
        try? await cache.evict(artifact)
        XCTAssertEqual(try Data(contentsOf: target), Data("valid fixture".utf8))
    }
}
