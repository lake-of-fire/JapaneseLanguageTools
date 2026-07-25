import XCTest
@testable import JapaneseLanguageTools

@MainActor
final class SpokenAudioSessionTests: XCTestCase {
    override func tearDown() {
        ManabiSpokenAudioSession.resetForTesting()
        super.tearDown()
    }

    func testLeasesReconcileIntentPriorityAndDeactivateOnlyAfterFinalRelease() throws {
        var events: [String] = []
        ManabiSpokenAudioSession.configurationOverrideForTesting = { intent in
            events.append("configure:\(intent)")
        }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = {
            events.append("deactivate")
        }

        let firstPronunciation = try ManabiSpokenAudioSession.acquire(.pronunciation)
        let secondPronunciation = try ManabiSpokenAudioSession.acquire(.pronunciation)
        let readAloud = try ManabiSpokenAudioSession.acquire(.readAloud)
        let recordedAudio = try ManabiSpokenAudioSession.acquire(.recordedAudio)

        XCTAssertEqual(events, [
            "configure:pronunciation",
            "configure:readAloud",
            "configure:recordedAudio"
        ])
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 4)

        try recordedAudio.release()
        try readAloud.release()
        try firstPronunciation.release()
        XCTAssertEqual(events, [
            "configure:pronunciation",
            "configure:readAloud",
            "configure:recordedAudio",
            "configure:readAloud",
            "configure:pronunciation"
        ])
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)

        try secondPronunciation.release()
        XCTAssertEqual(events.last, "deactivate")
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
    }

    func testFailedReconfigurationRetainsExistingLeaseState() throws {
        enum TestError: Error { case rejected }
        var shouldRejectRecordedAudio = true
        ManabiSpokenAudioSession.configurationOverrideForTesting = { intent in
            if intent == .recordedAudio, shouldRejectRecordedAudio {
                throw TestError.rejected
            }
        }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = {}

        let pronunciation = try ManabiSpokenAudioSession.acquire(.pronunciation)
        XCTAssertThrowsError(try ManabiSpokenAudioSession.acquire(.recordedAudio))
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)

        shouldRejectRecordedAudio = false
        let recordedAudio = try ManabiSpokenAudioSession.acquire(.recordedAudio)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 2)
        try recordedAudio.release()
        try pronunciation.release()
    }

    func testReleaseIsIdempotent() throws {
        var deactivationCount = 0
        ManabiSpokenAudioSession.configurationOverrideForTesting = { _ in }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = { deactivationCount += 1 }

        let lease = try ManabiSpokenAudioSession.acquire(.readAloud)
        try lease.release()
        try lease.release()

        XCTAssertEqual(deactivationCount, 1)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
    }

    func testFailedFinalDeactivationDoesNotAbandonLeaseOwnership() throws {
        enum TestError: Error { case rejected }
        var shouldRejectDeactivation = true
        var configurationCount = 0
        var deactivationCount = 0
        ManabiSpokenAudioSession.configurationOverrideForTesting = { _ in
            configurationCount += 1
        }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = {
            deactivationCount += 1
            if shouldRejectDeactivation {
                throw TestError.rejected
            }
        }

        let failedLease = try ManabiSpokenAudioSession.acquire(.readAloud)
        XCTAssertThrowsError(try failedLease.release())
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
        try failedLease.release()
        XCTAssertEqual(deactivationCount, 1)

        shouldRejectDeactivation = false
        let replacementLease = try ManabiSpokenAudioSession.acquire(.readAloud)
        XCTAssertEqual(configurationCount, 2)
        try replacementLease.release()
        XCTAssertEqual(deactivationCount, 2)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
    }

    func testFailedPriorityDowngradeRemovesLeaseAndRetriesUnknownConfiguration() throws {
        enum TestError: Error { case rejected }
        var configurations = [ManabiSpokenAudioIntent]()
        var shouldRejectPronunciation = false
        ManabiSpokenAudioSession.configurationOverrideForTesting = { intent in
            configurations.append(intent)
            if intent == .pronunciation, shouldRejectPronunciation {
                shouldRejectPronunciation = false
                throw TestError.rejected
            }
        }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = {}

        let pronunciation = try ManabiSpokenAudioSession.acquire(.pronunciation)
        let recordedAudio = try ManabiSpokenAudioSession.acquire(.recordedAudio)
        shouldRejectPronunciation = true

        XCTAssertThrowsError(try recordedAudio.release())
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
        try recordedAudio.release()

        let secondPronunciation = try ManabiSpokenAudioSession.acquire(.pronunciation)
        XCTAssertEqual(
            configurations,
            [.pronunciation, .recordedAudio, .pronunciation, .pronunciation]
        )
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 2)

        try secondPronunciation.release()
        try pronunciation.release()
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
    }
}
