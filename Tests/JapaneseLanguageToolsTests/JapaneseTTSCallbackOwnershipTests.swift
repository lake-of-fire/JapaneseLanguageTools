import Speech
import XCTest
@testable import JapaneseLanguageTools

@MainActor
final class JapaneseTTSCallbackOwnershipTests: XCTestCase {
    override func tearDown() {
        ManabiSpokenAudioSession.resetForTesting()
        super.tearDown()
    }

    private func start(_ text: String, on speaker: JapaneseTTS) async throws -> AVSpeechUtterance {
        let started = expectation(description: "synthesized pronunciation started")
        var captured: AVSpeechUtterance?
        speaker.synthesizedSpeechStartOverride = { utterance in
            captured = utterance
            started.fulfill()
        }
        speaker.speakJapanese(expression: text)
        await fulfillment(of: [started], timeout: 2)
        return try XCTUnwrap(captured)
    }

    func test_replacedUtteranceCallbacks_preserveCurrentPlaybackAndLease() async throws {
        ManabiSpokenAudioSession.configurationOverrideForTesting = { _ in }
        var deactivations = 0
        ManabiSpokenAudioSession.deactivationOverrideForTesting = { deactivations += 1 }
        let speaker = JapaneseTTS()
        let old = try await start("古い", on: speaker)
        let current = try await start("新しい", on: speaker)
        let afterReplacement = deactivations

        speaker.handleSynthesizedUtteranceEvent(.paused, utterance: old)
        speaker.handleSynthesizedUtteranceEvent(.finished, utterance: old)
        XCTAssertTrue(speaker.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
        XCTAssertEqual(deactivations, afterReplacement)

        speaker.handleSynthesizedUtteranceEvent(.finished, utterance: current)
        XCTAssertFalse(speaker.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
        XCTAssertEqual(deactivations, afterReplacement + 1)
        speaker.handleSynthesizedUtteranceEvent(.finished, utterance: current)
        speaker.handleSynthesizedUtteranceEvent(.playing, utterance: old)
        XCTAssertFalse(speaker.isPlaying)
        XCTAssertEqual(deactivations, afterReplacement + 1)
    }

    func test_matchingPauseAndResume_keepLeaseUntilCompletion() async throws {
        ManabiSpokenAudioSession.configurationOverrideForTesting = { _ in }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = {}
        let speaker = JapaneseTTS()
        let utterance = try await start("日本語", on: speaker)

        speaker.handleSynthesizedUtteranceEvent(.paused, utterance: utterance)
        XCTAssertFalse(speaker.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
        speaker.handleSynthesizedUtteranceEvent(.playing, utterance: utterance)
        XCTAssertTrue(speaker.isPlaying)
        speaker.handleSynthesizedUtteranceEvent(.finished, utterance: utterance)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
    }

    func test_foreignUtteranceCompletion_doesNotReleaseAnotherSpeakerLease() async throws {
        ManabiSpokenAudioSession.configurationOverrideForTesting = { _ in }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = {}
        let first = JapaneseTTS()
        let second = JapaneseTTS()
        let firstUtterance = try await start("一", on: first)
        let secondUtterance = try await start("二", on: second)

        first.handleSynthesizedUtteranceEvent(.finished, utterance: secondUtterance)
        second.handleSynthesizedUtteranceEvent(.finished, utterance: firstUtterance)
        XCTAssertTrue(first.isPlaying)
        XCTAssertTrue(second.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 2)
        first.handleSynthesizedUtteranceEvent(.finished, utterance: firstUtterance)
        XCTAssertTrue(second.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
        second.handleSynthesizedUtteranceEvent(.finished, utterance: secondUtterance)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
    }
}
