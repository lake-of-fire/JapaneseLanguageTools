#if DEBUG
import AVFoundation
import Combine
import Foundation
import XCTest
@testable import JapaneseLanguageTools

final class OwnedPronunciationTests: XCTestCase {
    @MainActor
    func testCancellingQueuedRequestNeverStartsAndFinishesOnce() async throws {
        let tts = makeTTS()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        var utterances = [AVSpeechUtterance]()
        tts.synthesizedSpeechStartOverride = { utterances.append($0) }
        let finished = expectation(description: "queued request finished")
        var finishedIDs = [UUID]()

        let id = tts.startPronunciation(expression: "よみ") {
            finishedIDs.append($0)
            finished.fulfill()
        }
        let queued = try XCTUnwrap(tts.speechRequestTaskForTesting)
        tts.cancelPronunciation(id)
        tts.cancelPronunciation(id)
        XCTAssertTrue(finishedIDs.isEmpty)

        await queued.value
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(finishedIDs, [id])
        XCTAssertTrue(utterances.isEmpty)
        XCTAssertFalse(tts.isPlaying)
    }

    @MainActor
    func testCancellingDownloadRejectsLateAudioAndClearsOwner() async throws {
        let tts = makeTTS()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        let expression = "owned-download-\(UUID().uuidString)"
        let downloaded = FileManager.default.temporaryDirectory.appendingPathComponent(expression)
        let cache = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
            .appendingPathComponent("audio").appendingPathComponent("tofugu")
            .appendingPathComponent("\(expression)【よみ】.mp3")
        try Data([0]).write(to: downloaded)
        defer {
            try? FileManager.default.removeItem(at: downloaded)
            try? FileManager.default.removeItem(at: cache)
        }

        let gate = DownloadGate()
        let started = expectation(description: "download is pending")
        let finished = expectation(description: "download's request finished")
        var finishedID: UUID?
        var playCount = 0
        tts.pronunciationAudioURLResolver = { _, _ in URL(string: "https://example.com/audio.mp3") }
        tts.pronunciationAudioDownloader = .init { _ in
            started.fulfill()
            return await gate.waitForURL()
        }
        tts.recordedAudioPlaybackOverride = { _, _, _, _, _ in playCount += 1 }
        tts.synthesizedSpeechStartOverride = { _ in playCount += 1 }

        let id = tts.startPronunciation(expression: expression, readingKana: "よみ") {
            finishedID = $0
            finished.fulfill()
        }
        let preparation = try XCTUnwrap(tts.speechRequestTaskForTesting)
        await fulfillment(of: [started], timeout: 1)
        tts.cancelPronunciation(id)
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(finishedID, id)
        XCTAssertFalse(tts.isPlaying)

        await gate.deliver(downloaded)
        await preparation.value
        XCTAssertEqual(playCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
    }

    @MainActor
    func testCancellingPlaybackReleasesOnlyTheOwnedLease() async throws {
        let tts = makeTTS()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        let readAloud = try ManabiSpokenAudioSession.acquire(.readAloud)
        defer { try? readAloud.release() }
        var utterance: AVSpeechUtterance?
        tts.synthesizedSpeechStartOverride = { utterance = $0 }
        let finished = expectation(description: "playing request finished")
        var finishedID: UUID?

        let id = tts.startPronunciation(expression: "よみ") {
            finishedID = $0
            finished.fulfill()
        }
        let preparation = try XCTUnwrap(tts.speechRequestTaskForTesting)
        await preparation.value
        XCTAssertTrue(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 2)

        tts.cancelPronunciation(id)
        tts.handleSynthesizedUtteranceEvent(try XCTUnwrap(utterance))
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(finishedID, id)
        XCTAssertFalse(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
    }

    @MainActor
    func testStaleStopCannotCancelLegacyReplacement() async throws {
        let tts = makeTTS()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        var utterances = [AVSpeechUtterance]()
        tts.synthesizedSpeechStartOverride = { utterances.append($0) }
        let replaced = expectation(description: "old request was retired by legacy start")
        var replacedID: UUID?

        let oldID = tts.startPronunciation(expression: "さいしょ") {
            replacedID = $0
            replaced.fulfill()
        }
        let initial = try XCTUnwrap(tts.speechRequestTaskForTesting)
        await initial.value
        tts.speakJapanese(expression: "つぎ")
        let replacement = try XCTUnwrap(tts.speechRequestTaskForTesting)
        await replacement.value
        await fulfillment(of: [replaced], timeout: 1)
        XCTAssertEqual(replacedID, oldID)

        tts.cancelPronunciation(oldID)
        tts.handleSynthesizedUtteranceEvent(try XCTUnwrap(utterances.first))
        XCTAssertEqual(utterances.count, 2)
        XCTAssertTrue(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
        tts.handleSynthesizedUtteranceEvent(try XCTUnwrap(utterances.last))
        XCTAssertFalse(tts.isPlaying)
    }

    @MainActor
    func testTerminalFailureAndNaturalEndNotifyTheirOwnRequests() async throws {
        struct ActivationFailure: Error {}

        let tts = makeTTS()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        var utterance: AVSpeechUtterance?
        tts.synthesizedSpeechStartOverride = { utterance = $0 }
        ManabiSpokenAudioSession.activationOverrideForTesting = { _ in throw ActivationFailure() }

        let failed = expectation(description: "failed request finished")
        var finishedIDs = [UUID]()
        let failedID = tts.startPronunciation(expression: "よみ") {
            finishedIDs.append($0)
            failed.fulfill()
        }
        await fulfillment(of: [failed], timeout: 1)
        XCTAssertEqual(finishedIDs, [failedID])
        XCTAssertNil(utterance)
        XCTAssertFalse(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)

        ManabiSpokenAudioSession.activationOverrideForTesting = { _ in }
        let finished = expectation(description: "successful pronunciation finished")
        let id = tts.startPronunciation(expression: "よみ") {
            finishedIDs.append($0)
            finished.fulfill()
        }
        let preparation = try XCTUnwrap(tts.speechRequestTaskForTesting)
        await preparation.value
        XCTAssertTrue(tts.isPlaying)
        XCTAssertEqual(finishedIDs, [failedID])
        let spoken = try XCTUnwrap(utterance)
        tts.handleSynthesizedUtteranceEvent(spoken)
        tts.handleSynthesizedUtteranceEvent(spoken)
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(finishedIDs, [failedID, id])
        XCTAssertFalse(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
    }

    @MainActor
    func testSynchronousPlayingObserverCanCancelBeforeSpeechStarts() async throws {
        let tts = makeTTS()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        var utterances = [AVSpeechUtterance]()
        tts.synthesizedSpeechStartOverride = { utterances.append($0) }
        let finished = expectation(description: "observer canceled request")
        let id = tts.startPronunciation(expression: "よみ") { _ in finished.fulfill() }
        let preparation = try XCTUnwrap(tts.speechRequestTaskForTesting)
        let observer = tts.$isPlaying.sink { playing in
            if playing { tts.cancelPronunciation(id) }
        }
        defer { observer.cancel() }

        await preparation.value
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertTrue(utterances.isEmpty)
        XCTAssertFalse(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
    }

    @MainActor
    func testRequestStartedDuringResetOwnsPlaybackAfterOuterCleanup() async throws {
        let tts = makeTTS()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        var utterances = [AVSpeechUtterance]()
        tts.synthesizedSpeechStartOverride = { utterances.append($0) }
        tts.speakJapanese(expression: "さいしょ")
        let initial = try XCTUnwrap(tts.speechRequestTaskForTesting)
        await initial.value

        var startedReplacement = false
        let observer = tts.$isPlaying.sink { playing in
            guard !playing, !startedReplacement else { return }
            startedReplacement = true
            tts.speakJapanese(expression: "あたらしい")
        }
        defer { observer.cancel() }
        let replaced = expectation(description: "outer request was retired by observer's start")
        var replacedID: UUID?
        let id = tts.startPronunciation(expression: "ふるい") {
            replacedID = $0
            replaced.fulfill()
        }
        let replacement = try XCTUnwrap(tts.speechRequestTaskForTesting)
        await replacement.value
        await fulfillment(of: [replaced], timeout: 1)

        XCTAssertTrue(startedReplacement)
        XCTAssertEqual(replacedID, id)
        XCTAssertEqual(utterances.map(\.speechString), ["サイショ", "アタラシー"])
        XCTAssertTrue(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
        tts.handleSynthesizedUtteranceEvent(try XCTUnwrap(utterances.last))
        XCTAssertFalse(tts.isPlaying)
    }

    @MainActor
    private func makeTTS() -> JapaneseTTS {
        ManabiSpokenAudioSession.resetForTesting()
        ManabiSpokenAudioSession.activationOverrideForTesting = { _ in }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = {}
        let tts = JapaneseTTS()
        tts.synthesizedSpeechVoiceResolverOverride = { nil }
        return tts
    }

    private actor DownloadGate {
        private var url: URL?
        private var continuation: CheckedContinuation<URL, Never>?

        func waitForURL() async -> URL {
            if let url { return url }
            return await withCheckedContinuation { continuation = $0 }
        }

        func deliver(_ url: URL) {
            self.url = url
            continuation?.resume(returning: url)
            continuation = nil
        }
    }
}
#endif
