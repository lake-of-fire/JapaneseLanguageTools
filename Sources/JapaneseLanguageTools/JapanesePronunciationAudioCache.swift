import CryptoKit
import Foundation

actor JapanesePronunciationAudioCache {
    static let shared = JapanesePronunciationAudioCache()

    struct Key: Hashable, Sendable {
        fileprivate let digest: String

        init(expression: String, readingKana: String, sourceURL: URL) throws {
            let values = [expression, readingKana, sourceURL.absoluteString]
            guard values.allSatisfy({ $0.utf8.count <= 4_096 }) else { throw URLError(.badURL) }
            let encoded = try JSONEncoder().encode(values)
            digest = SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
        }
    }

    struct Artifact: Sendable {
        let url: URL
        fileprivate let key: Key
        fileprivate let identifier: UUID
        fileprivate let identity: FileIdentity
    }

    fileprivate struct FileIdentity: Equatable, Sendable {
        let systemNumber: UInt64
        let fileNumber: UInt64
        let createdAt: Date
        let modifiedAt: Date
        let size: UInt64
    }

    private struct Manifest: Codable {
        let version: Int
        let identifier: UUID
    }

    private let directory: URL?
    private let validate: @Sendable (URL) throws -> Void

    init(
        directory: URL? = nil,
        validate: @escaping @Sendable (URL) throws -> Void = JapanesePronunciationAudioDownloader.validateAudioFile(at:)
    ) {
        self.directory = directory
        self.validate = validate
    }

    func cachedArtifact(for key: Key) throws -> Artifact? {
        let root = try cacheDirectory()
        let manifestURL = root.appendingPathComponent(key.digest + ".json")
        guard let identity = try? fileIdentity(at: manifestURL), identity.size <= 1_024 else { return nil }
        let handle = try FileHandle(forReadingFrom: manifestURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1_025) ?? Data()
        guard data.count <= 1_024,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data), manifest.version == 1 else {
            return nil
        }
        let url = artifactURL(root: root, key: key, identifier: manifest.identifier)
        do {
            let identity = try fileIdentity(at: url)
            try validate(url)
            guard try fileIdentity(at: url) == identity else { return nil }
            return Artifact(url: url, key: key, identifier: manifest.identifier, identity: identity)
        } catch {
            // A corrupt/missing hit never authorizes playback or path-based deletion.
            return nil
        }
    }

    func install(from temporaryURL: URL, for key: Key) throws -> Artifact {
        try Task.checkCancellation()
        let root = try cacheDirectory()
        let identifier = UUID()
        let staging = root.appendingPathComponent(identifier.uuidString + ".staging.mp3")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: temporaryURL, to: staging)
        try validate(staging)
        try Task.checkCancellation()
        let url = artifactURL(root: root, key: key, identifier: identifier)
        // Unique immutable names eliminate existence-check/winner races. Concurrent
        // installers may each play their valid artifact; the last manifest wins.
        try FileManager.default.moveItem(at: staging, to: url)
        let identity = try fileIdentity(at: url)
        let manifest = Manifest(version: 1, identifier: identifier)
        try JSONEncoder().encode(manifest).write(
            to: root.appendingPathComponent(key.digest + ".json"), options: .atomic
        )
        return Artifact(url: url, key: key, identifier: identifier, identity: identity)
    }

    func evict(_ artifact: Artifact) throws {
        let root = try cacheDirectory()
        let expectedURL = artifactURL(root: root, key: artifact.key, identifier: artifact.identifier)
        guard artifact.url == expectedURL, try fileIdentity(at: expectedURL) == artifact.identity else { return }
        try FileManager.default.removeItem(at: expectedURL)
        // Do not remove the key's manifest: a successor may have replaced it.
        // A manifest still pointing here becomes a cache miss on the next read.
    }

    private func artifactURL(root: URL, key: Key, identifier: UUID) -> URL {
        root.appendingPathComponent(key.digest + "-" + identifier.uuidString + ".mp3")
    }

    private func cacheDirectory() throws -> URL {
        let root: URL
        if let directory {
            root = directory
        } else {
            root = try FileManager.default.url(
                for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            ).appendingPathComponent("audio/tofugu-v2", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw URLError(.cannotCreateFile) }
        return root.resolvingSymlinksInPath().standardizedFileURL
    }

    private func fileIdentity(at url: URL) throws -> FileIdentity {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let systemNumber = attributes[.systemNumber] as? NSNumber,
              let fileNumber = attributes[.systemFileNumber] as? NSNumber,
              let createdAt = attributes[.creationDate] as? Date,
              let modifiedAt = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? NSNumber else { throw URLError(.cannotOpenFile) }
        return FileIdentity(
            systemNumber: systemNumber.uint64Value, fileNumber: fileNumber.uint64Value,
            createdAt: createdAt, modifiedAt: modifiedAt, size: size.uint64Value
        )
    }
}
