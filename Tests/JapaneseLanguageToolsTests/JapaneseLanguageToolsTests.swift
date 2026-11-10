import XCTest
import AVFoundation
@testable import JapaneseLanguageTools

final class JapaneseLanguageToolsTests: XCTestCase {
    func testPronunciationDownloadRejectsHTTPErrorBodies() throws {
        let url = URL(string: "https://example.com/audio.mp3")!
        for status in [200, 206] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            XCTAssertNoThrow(try JapanesePronunciationAudioDownloader.validate(response: response))
        }
        for status in [301, 404, 429, 500] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            XCTAssertThrowsError(try JapanesePronunciationAudioDownloader.validate(response: response))
        }
        XCTAssertThrowsError(try JapanesePronunciationAudioDownloader.validate(
            response: URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        ))
    }

#if DEBUG
    @MainActor
    func testFailedRecordedPronunciationEvictsCacheAndFallsBackToSynthesis() async throws {
        ManabiSpokenAudioSession.resetForTesting()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        configureAudioSessionForTesting()

        let expression = "recorded-failure-\(UUID().uuidString)"
        let reading = "よみ"
        let remoteURL = URL(string: "https://example.com/\(expression).mp3")!
        let downloadedURL = try makeTemporaryAudioFile()
        let cachedURL = try pronunciationCacheURL(expression: expression, reading: reading)
        defer { try? FileManager.default.removeItem(at: cachedURL) }
        let tts = JapaneseTTS()
        tts.synthesizedSpeechVoiceResolverOverride = { nil }
        var recordedReady: (() -> Void)?
        var recordedFailure: (() -> Void)?
        var synthesizedUtterance: AVSpeechUtterance?
        let recordedPlaybackStarted = expectation(description: "recorded playback started")
        let speechFinished = expectation(description: "synthesized speech finished")
        tts.pronunciationAudioURLResolver = { _, _ in remoteURL }
        tts.pronunciationAudioDownloader = .init { _ in downloadedURL }
        tts.recordedAudioPlaybackOverride = { _, _, ready, _, failed in
            recordedReady = ready
            recordedFailure = failed
            recordedPlaybackStarted.fulfill()
        }
        tts.synthesizedSpeechStartOverride = { utterance in synthesizedUtterance = utterance }

        tts.speakJapanese(expression: expression, readingKana: reading)
        await fulfillment(of: [recordedPlaybackStarted], timeout: 1)

        XCTAssertTrue(FileManager.default.fileExists(atPath: cachedURL.path))
        try XCTUnwrap(recordedReady)()
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
        XCTAssertNotNil(recordedFailure)
        recordedFailure?()

        XCTAssertFalse(FileManager.default.fileExists(atPath: cachedURL.path))
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
        let secondCachedURL = try pronunciationCacheURL(expression: secondExpression, reading: "よみ")
        defer { try? FileManager.default.removeItem(at: secondCachedURL) }
        let tts = JapaneseTTS()
        tts.synthesizedSpeechVoiceResolverOverride = { nil }
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
        tts.synthesizedSpeechVoiceResolverOverride = { nil }
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

        tts.handleSynthesizedUtteranceEvent(first)
        tts.handleSynthesizedUtteranceEvent(first)
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
        ManabiSpokenAudioSession.activationOverrideForTesting = { _ in activations += 1 }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = { deactivations += 1 }
        let expression = "recorded-success-\(UUID().uuidString)"
        let downloaded = try makeTemporaryAudioFile()
        let cached = try pronunciationCacheURL(expression: expression, reading: "よみ")
        defer {
            try? FileManager.default.removeItem(at: downloaded)
            try? FileManager.default.removeItem(at: cached)
        }
        let tts = JapaneseTTS()
        tts.synthesizedSpeechVoiceResolverOverride = { nil }
        let started = expectation(description: "recorded item loaded")
        var ready: (() -> Void)?
        var finished: (() -> Void)?
        tts.pronunciationAudioURLResolver = { _, _ in URL(string: "https://example.com/audio.mp3") }
        tts.pronunciationAudioDownloader = .init { _ in downloaded }
        tts.recordedAudioPlaybackOverride = { _, _, onReady, onFinish, _ in
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: cached.path))
    }

    @MainActor
    func testSynthesizedSessionActivationFailureStopsRequestAndAllowsRecovery() async throws {
        ManabiSpokenAudioSession.resetForTesting()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        struct ExpectedFailure: Error {}
        var activationCount = 0
        var deactivationCount = 0
        ManabiSpokenAudioSession.activationOverrideForTesting = { intent in
            XCTAssertEqual(intent, .pronunciation)
            activationCount += 1
            throw ExpectedFailure()
        }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = { deactivationCount += 1 }
        let tts = JapaneseTTS()
        var voiceResolutionCount = 0
        tts.synthesizedSpeechVoiceResolverOverride = {
            voiceResolutionCount += 1
            return nil
        }
        var utterances = [AVSpeechUtterance]()
        tts.synthesizedSpeechStartOverride = { utterances.append($0) }
        let failedRequestFinished = expectation(description: "failed synthesized request finished")
        tts.speechRequestCompletionOverride = { failedRequestFinished.fulfill() }

        tts.speakJapanese(expression: "よみ")
        await fulfillment(of: [failedRequestFinished], timeout: 1)
        XCTAssertTrue(utterances.isEmpty)
        XCTAssertFalse(tts.isPlaying)
        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(deactivationCount, 0)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)

        ManabiSpokenAudioSession.activationOverrideForTesting = { _ in activationCount += 1 }
        let recoveryStarted = expectation(description: "replacement synthesized request started")
        tts.speechRequestCompletionOverride = { recoveryStarted.fulfill() }
        tts.speakJapanese(expression: "よみ")
        await fulfillment(of: [recoveryStarted], timeout: 1)
        XCTAssertEqual(utterances.count, 1)
        XCTAssertTrue(tts.isPlaying)
        XCTAssertEqual(activationCount, 2)
        XCTAssertEqual(voiceResolutionCount, 1,
            "A missing voice is resolved once across failed and recovered speech requests")
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
        tts.handleSynthesizedUtteranceEvent(try XCTUnwrap(utterances.last))
        XCTAssertFalse(tts.isPlaying)
        XCTAssertEqual(deactivationCount, 1)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
    }

    @MainActor
    func testRecordedSessionActivationFailureRetainsCacheAndRejectsObsoleteEvents() async throws {
        ManabiSpokenAudioSession.resetForTesting()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        struct ExpectedFailure: Error {}
        var activationCount = 0
        var deactivationCount = 0
        ManabiSpokenAudioSession.activationOverrideForTesting = { intent in
            XCTAssertEqual(intent, .pronunciation)
            activationCount += 1
            throw ExpectedFailure()
        }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = { deactivationCount += 1 }
        let expression = "recorded-activation-failure-\(UUID().uuidString)"
        let downloaded = try makeTemporaryAudioFile()
        let cached = try pronunciationCacheURL(expression: expression, reading: "よみ")
        defer {
            try? FileManager.default.removeItem(at: downloaded)
            try? FileManager.default.removeItem(at: cached)
        }
        let tts = JapaneseTTS()
        tts.synthesizedSpeechVoiceResolverOverride = { nil }
        var playbackStarts = 0
        var synthesizedStarts = 0
        var downloadCount = 0
        var ready: (() -> Void)?
        var finished: (() -> Void)?
        var failed: (() -> Void)?
        tts.pronunciationAudioURLResolver = { _, _ in URL(string: "https://example.com/audio.mp3") }
        tts.pronunciationAudioDownloader = .init { _ in
            downloadCount += 1
            return downloaded
        }
        tts.recordedAudioStartOverride = { playbackStarts += 1 }
        tts.synthesizedSpeechStartOverride = { _ in synthesizedStarts += 1 }
        let firstLoaded = expectation(description: "first recorded item loaded")
        tts.recordedAudioPlaybackOverride = { _, _, onReady, onFinish, onFailure in
            ready = onReady
            finished = onFinish
            failed = onFailure
            firstLoaded.fulfill()
        }
        tts.speakJapanese(expression: expression, readingKana: "よみ")
        await fulfillment(of: [firstLoaded], timeout: 1)
        let oldReady = try XCTUnwrap(ready)
        let oldFinished = try XCTUnwrap(finished)
        let oldFailed = try XCTUnwrap(failed)
        oldReady()
        oldReady()
        oldFinished()
        oldFailed()
        XCTAssertEqual(playbackStarts, 0)
        XCTAssertEqual(synthesizedStarts, 0)
        XCTAssertFalse(tts.isPlaying)
        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(deactivationCount, 0)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
        XCTAssertEqual(try Data(contentsOf: cached), Data([0]))

        ManabiSpokenAudioSession.activationOverrideForTesting = { _ in activationCount += 1 }
        let recoveryLoaded = expectation(description: "replacement recorded item loaded")
        tts.recordedAudioPlaybackOverride = { _, _, onReady, onFinish, _ in
            ready = onReady
            finished = onFinish
            recoveryLoaded.fulfill()
        }
        tts.speakJapanese(expression: expression, readingKana: "よみ")
        await fulfillment(of: [recoveryLoaded], timeout: 1)
        try XCTUnwrap(ready)()
        oldReady()
        oldFinished()
        oldFailed()
        XCTAssertEqual(playbackStarts, 1)
        XCTAssertEqual(synthesizedStarts, 0)
        XCTAssertTrue(tts.isPlaying)
        XCTAssertEqual(activationCount, 2)
        XCTAssertEqual(downloadCount, 1)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
        XCTAssertEqual(try Data(contentsOf: cached), Data([0]))
        try XCTUnwrap(finished)()
        XCTAssertFalse(tts.isPlaying)
        XCTAssertEqual(deactivationCount, 1)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
    }

    private func makeTemporaryAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")
        try Data([0]).write(to: url)
        return url
    }

    private func pronunciationCacheURL(expression: String, reading: String) throws -> URL {
        let directory = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return directory
            .appendingPathComponent("audio")
            .appendingPathComponent("tofugu")
            .appendingPathComponent("\(expression)【\(reading)】.mp3")
    }

    @MainActor
    private func configureAudioSessionForTesting() {
        ManabiSpokenAudioSession.activationOverrideForTesting = { _ in }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = {}
    }
#endif
}
