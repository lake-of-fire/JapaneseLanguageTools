import XCTest
import AVFoundation
@testable import JapaneseLanguageTools

final class JapaneseTTSRecordedPlaybackTests: XCTestCase {
    @MainActor
    func testFailedRecordedPronunciationEvictsCacheAndFallsBackToSynthesis() async throws {
        ManabiSpokenAudioSession.resetForTesting()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        configureAudioSessionForTesting()

        let expression = "recorded-failure-\(UUID().uuidString)"
        let reading = "よみ"
        let remoteURL = URL(string: "https://example.com/\(expression).mp3")!
        let downloadedURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: downloadedURL) }
        let tts = JapaneseTTS()
        let cache = try makePronunciationCache()
        tts.pronunciationAudioCache = cache
        var cachedURL: URL?
        var recordedReady: (() -> Void)?
        var recordedFailure: (() -> Void)?
        var synthesizedUtterance: AVSpeechUtterance?
        var synthesisStarts = 0
        let recordedPlaybackStarted = expectation(description: "recorded playback started")
        let speechFinished = expectation(description: "synthesized speech finished")
        let cacheEvicted = expectation(description: "failed artifact eviction completed")
        tts.pronunciationArtifactEvictionCompletionOverride = { url in
            XCTAssertEqual(url, cachedURL)
            cacheEvicted.fulfill()
        }
        tts.pronunciationAudioURLResolver = { _, _ in remoteURL }
        tts.pronunciationAudioDownloader = .init { _ in downloadedURL }
        tts.recordedAudioPlaybackOverride = { url, _, ready, _, failed in
            cachedURL = url
            recordedReady = ready
            recordedFailure = failed
            recordedPlaybackStarted.fulfill()
        }
        tts.synthesizedSpeechStartOverride = { utterance in
            synthesizedUtterance = utterance
            synthesisStarts += 1
        }

        tts.speakJapanese(expression: expression, readingKana: reading)
        await fulfillment(of: [recordedPlaybackStarted], timeout: 1)

        let playedURL = try XCTUnwrap(cachedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: playedURL.path))
        try XCTUnwrap(recordedReady)()
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
        // Another installer may publish this key while the old bytes are playing.
        let successorInput = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: successorInput) }
        let key = try JapanesePronunciationAudioCache.Key(
            expression: expression, readingKana: reading, sourceURL: remoteURL
        )
        let successor = try await cache.install(from: successorInput, for: key)
        try XCTUnwrap(recordedFailure)()

        await fulfillment(of: [cacheEvicted], timeout: 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: playedURL.path))
        let current = try await cache.cachedArtifact(for: key)
        XCTAssertEqual(current?.url, successor.url)
        // These callbacks still carry the same speech request, but the recorded
        // playback authority was retired by the transition to synthesis.
        try XCTUnwrap(recordedFailure)()
        try XCTUnwrap(recordedReady)()
        XCTAssertEqual(synthesisStarts, 1)
        XCTAssertEqual(synthesizedUtterance?.speechString, "ヨミ")
        XCTAssertTrue(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)

        ManabiSpokenAudioSession.deactivationOverrideForTesting = { speechFinished.fulfill() }
        tts.speechSynthesizer(AVSpeechSynthesizer(), didFinish: try XCTUnwrap(synthesizedUtterance))
        await fulfillment(of: [speechFinished], timeout: 1)
        XCTAssertFalse(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
    }

    @MainActor
    func testSupersededDownloadAndRecordedCompletionCannotFinishReplacement() async throws {
        ManabiSpokenAudioSession.resetForTesting()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        configureAudioSessionForTesting()

        let firstExpression = "superseded-download-\(UUID().uuidString)"
        let firstDownloadedURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: firstDownloadedURL) }
        let secondExpression = "superseded-player-\(UUID().uuidString)"
        let secondDownloadedURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: secondDownloadedURL) }
        let tts = JapaneseTTS()
        tts.pronunciationAudioCache = try makePronunciationCache()
        var resumeFirstDownload: CheckedContinuation<URL, Error>?
        var recordedReady: (() -> Void)?
        var recordedCompletion: (() -> Void)?
        var recordedFailure: (() -> Void)?
        var synthesizedUtterances = [AVSpeechUtterance]()
        let firstDownloadStarted = expectation(description: "first download started")
        let replacementStarted = expectation(description: "replacement synthesis started")
        let recordedPlaybackStarted = expectation(description: "recorded playback started")
        let finalReplacementStarted = expectation(description: "final replacement synthesis started")
        let finalReplacementFinished = expectation(description: "final replacement synthesis finished")
        tts.pronunciationAudioURLResolver = { expression, _ in
            URL(string: "https://example.com/\(expression).mp3")
        }
        tts.pronunciationAudioDownloader = .init { _ in
            try await withCheckedThrowingContinuation { continuation in
                resumeFirstDownload = continuation
                firstDownloadStarted.fulfill()
            }
        }
        tts.recordedAudioPlaybackOverride = { _, _, ready, finished, failed in
            recordedReady = ready
            recordedCompletion = finished
            recordedFailure = failed
            recordedPlaybackStarted.fulfill()
        }
        tts.synthesizedSpeechStartOverride = { utterance in
            synthesizedUtterances.append(utterance)
            if synthesizedUtterances.count == 1 {
                replacementStarted.fulfill()
            } else {
                finalReplacementStarted.fulfill()
            }
        }

        tts.speakJapanese(expression: firstExpression, readingKana: "よみ")
        await fulfillment(of: [firstDownloadStarted], timeout: 1)
        tts.speakJapanese(expression: "replacement", readingKana: nil)
        await fulfillment(of: [replacementStarted], timeout: 1)
        let replacementUtterance = try XCTUnwrap(synthesizedUtterances.last)

        let supersededDownloadFinished = expectation(description: "superseded download request finished")
        tts.speechRequestCompletionOverride = { supersededDownloadFinished.fulfill() }
        try XCTUnwrap(resumeFirstDownload).resume(returning: firstDownloadedURL)
        await fulfillment(of: [supersededDownloadFinished], timeout: 1)
        tts.speechRequestCompletionOverride = nil
        XCTAssertNil(recordedCompletion)
        XCTAssertTrue(tts.isPlaying)

        // Exercise the same request fence after an old player has already started.
        tts.pronunciationAudioDownloader = .init { _ in secondDownloadedURL }
        tts.speakJapanese(expression: secondExpression, readingKana: "よみ")
        await fulfillment(of: [recordedPlaybackStarted], timeout: 1)
        try XCTUnwrap(recordedReady)()
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
        let oldRecordedCompletion = try XCTUnwrap(recordedCompletion)
        let oldRecordedFailure = try XCTUnwrap(recordedFailure)
        tts.speakJapanese(expression: "replacement-again", readingKana: nil)
        await fulfillment(of: [finalReplacementStarted], timeout: 1)
        let finalUtterance = try XCTUnwrap(synthesizedUtterances.last)

        oldRecordedCompletion()
        oldRecordedFailure()
        XCTAssertTrue(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
        ManabiSpokenAudioSession.deactivationOverrideForTesting = { finalReplacementFinished.fulfill() }
        tts.speechSynthesizer(AVSpeechSynthesizer(), didFinish: finalUtterance)
        await fulfillment(of: [finalReplacementFinished], timeout: 1)
        XCTAssertFalse(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
        XCTAssertFalse(replacementUtterance === finalUtterance)
    }

    @MainActor
    func testObsoleteSynthesizedFinishAndCancelDoNotReleaseCurrentRequestLease() async throws {
        ManabiSpokenAudioSession.resetForTesting()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        configureAudioSessionForTesting()

        let tts = JapaneseTTS()
        var utterances = [AVSpeechUtterance]()
        let firstStarted = expectation(description: "first synthesis started")
        let secondStarted = expectation(description: "second synthesis started")
        let secondFinished = expectation(description: "second synthesis finished")
        tts.synthesizedSpeechStartOverride = { utterance in
            utterances.append(utterance)
            if utterances.count == 1 {
                firstStarted.fulfill()
            } else {
                secondStarted.fulfill()
            }
        }

        tts.speakJapanese(expression: "first", readingKana: nil)
        await fulfillment(of: [firstStarted], timeout: 1)
        let first = try XCTUnwrap(utterances.last)
        tts.speakJapanese(expression: "second", readingKana: nil)
        await fulfillment(of: [secondStarted], timeout: 1)
        let second = try XCTUnwrap(utterances.last)

        tts.handleSynthesizedUtteranceEvent(.finished, utterance: first)
        tts.handleSynthesizedUtteranceEvent(.finished, utterance: first)
        XCTAssertTrue(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)

        ManabiSpokenAudioSession.deactivationOverrideForTesting = { secondFinished.fulfill() }
        tts.speechSynthesizer(AVSpeechSynthesizer(), didCancel: second)
        await fulfillment(of: [secondFinished], timeout: 1)
        XCTAssertFalse(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
    }

    @MainActor
    func testRecordedReadyAndFinishAcquireAndReleaseExactlyOneLease() async throws {
        ManabiSpokenAudioSession.resetForTesting()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        var activations = 0
        var deactivations = 0
        ManabiSpokenAudioSession.configurationOverrideForTesting = { _ in activations += 1 }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = { deactivations += 1 }
        let expression = "recorded-success-\(UUID().uuidString)"
        let downloaded = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: downloaded) }
        let tts = JapaneseTTS()
        tts.pronunciationAudioCache = try makePronunciationCache()
        var cachedURL: URL?
        let started = expectation(description: "recorded item loaded")
        var ready: (() -> Void)?
        var finished: (() -> Void)?
        tts.pronunciationAudioURLResolver = { _, _ in URL(string: "https://example.com/audio.mp3") }
        tts.pronunciationAudioDownloader = .init { _ in downloaded }
        tts.recordedAudioPlaybackOverride = { url, _, onReady, onFinish, _ in
            cachedURL = url
            ready = onReady
            finished = onFinish
            started.fulfill()
        }
        tts.speakJapanese(expression: expression, readingKana: "よみ")
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
        try XCTUnwrap(ready)()
        try XCTUnwrap(ready)()
        XCTAssertTrue(tts.isPlaying)
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
        try XCTUnwrap(finished)()
        try XCTUnwrap(finished)()
        try XCTUnwrap(ready)()
        XCTAssertFalse(tts.isPlaying)
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(deactivations, 1)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(cachedURL).path))
    }

    private func makeTemporaryAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")
        try Data([0]).write(to: url)
        return url
    }

    private func makePronunciationCache() throws -> JapanesePronunciationAudioCache {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return JapanesePronunciationAudioCache(directory: directory) { url in
            // Playback ownership uses a fixture validator; production MP3 decoding is separate.
            guard try Data(contentsOf: url) == Data([0]) else {
                throw URLError(.cannotDecodeContentData)
            }
        }
    }

    @MainActor
    private func configureAudioSessionForTesting() {
        ManabiSpokenAudioSession.configurationOverrideForTesting = { _ in }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = {}
    }

}
