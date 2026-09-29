import XCTest
@testable import JapaneseLanguageTools

#if DEBUG
@MainActor
final class SpokenAudioSessionPriorityTests: XCTestCase {
    override func tearDown() {
        ManabiSpokenAudioSession.resetForTesting()
        super.tearDown()
    }

    func testLeasesReconcileIntentPriorityAndDeactivateAfterFinalRelease() throws {
        var events: [String] = []
        ManabiSpokenAudioSession.activationOverrideForTesting = {
            events.append("configure:\($0)")
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
            "configure:recordedAudio",
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
            "configure:pronunciation",
        ])

        try secondPronunciation.release()
        XCTAssertEqual(events.last, "deactivate")
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
    }

    func testLowerPriorityLeaseDoesNotReconfigureHigherPrioritySession() throws {
        var configured: [ManabiSpokenAudioIntent] = []
        ManabiSpokenAudioSession.activationOverrideForTesting = { configured.append($0) }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = {}

        let readAloud = try ManabiSpokenAudioSession.acquire(.readAloud)
        let pronunciation = try ManabiSpokenAudioSession.acquire(.pronunciation)

        XCTAssertEqual(configured, [.readAloud])
        try pronunciation.release()
        XCTAssertEqual(configured, [.readAloud])
        try readAloud.release()
    }

    func testFailedHigherPriorityAcquisitionKeepsExistingLease() throws {
        enum TestError: Error { case rejected }
        var rejectRecordedAudio = true
        ManabiSpokenAudioSession.activationOverrideForTesting = { intent in
            if intent == .recordedAudio, rejectRecordedAudio {
                throw TestError.rejected
            }
        }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = {}

        let pronunciation = try ManabiSpokenAudioSession.acquire(.pronunciation)
        XCTAssertThrowsError(try ManabiSpokenAudioSession.acquire(.recordedAudio))
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)

        rejectRecordedAudio = false
        let recordedAudio = try ManabiSpokenAudioSession.acquire(.recordedAudio)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 2)
        try recordedAudio.release()
        try pronunciation.release()
    }

    func testFailedFinalDeactivationEndsLogicalOwnershipAndRetriesUnknownState() throws {
        enum TestError: Error { case rejected }
        var rejectDeactivation = true
        var configurations = 0
        var deactivations = 0
        ManabiSpokenAudioSession.activationOverrideForTesting = { _ in configurations += 1 }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = {
            deactivations += 1
            if rejectDeactivation { throw TestError.rejected }
        }

        let failedLease = try ManabiSpokenAudioSession.acquire(.readAloud)
        XCTAssertThrowsError(try failedLease.release())
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)

        rejectDeactivation = false
        let replacement = try ManabiSpokenAudioSession.acquire(.readAloud)
        XCTAssertEqual(configurations, 2)
        try replacement.release()
        XCTAssertEqual(deactivations, 2)
    }

    func testFailedPriorityDowngradeRemovesReleasedLeaseAndRetriesUnknownState() throws {
        enum TestError: Error { case rejected }
        var configurations: [ManabiSpokenAudioIntent] = []
        var rejectPronunciation = false
        ManabiSpokenAudioSession.activationOverrideForTesting = { intent in
            configurations.append(intent)
            if intent == .pronunciation, rejectPronunciation {
                rejectPronunciation = false
                throw TestError.rejected
            }
        }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = {}

        let pronunciation = try ManabiSpokenAudioSession.acquire(.pronunciation)
        let recordedAudio = try ManabiSpokenAudioSession.acquire(.recordedAudio)
        rejectPronunciation = true

        XCTAssertThrowsError(try recordedAudio.release())
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)

        let secondPronunciation = try ManabiSpokenAudioSession.acquire(.pronunciation)
        XCTAssertEqual(
            configurations,
            [.pronunciation, .recordedAudio, .pronunciation, .pronunciation]
        )

        try secondPronunciation.release()
        try pronunciation.release()
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
    }
}
#endif
