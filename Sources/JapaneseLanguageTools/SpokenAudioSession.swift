import Foundation
#if os(iOS)
import AVFoundation
#endif

public enum ManabiSpokenAudioIntent: Equatable, Sendable {
    case pronunciation
    case readAloud
    case recordedAudio

    fileprivate var priority: Int {
        switch self {
        case .pronunciation: 0
        case .readAloud: 1
        case .recordedAudio: 2
        }
    }
}

@MainActor
public final class ManabiSpokenAudioSessionLease {
    fileprivate let id: UUID
    public let intent: ManabiSpokenAudioIntent
    private var isReleased = false

    fileprivate init(id: UUID, intent: ManabiSpokenAudioIntent) {
        self.id = id
        self.intent = intent
    }

    public func release() throws {
        guard !isReleased else { return }
        defer { isReleased = true }
        try ManabiSpokenAudioSession.release(id: id)
    }

    deinit {
        guard !isReleased else { return }
        let id = id
        Task { @MainActor in
            try? ManabiSpokenAudioSession.release(id: id)
        }
    }
}

@MainActor
public enum ManabiSpokenAudioSession {
    private enum AppliedState: Equatable {
        case inactive
        case configured(ManabiSpokenAudioIntent)
        case unknown
    }

    private static var activeLeases: [UUID: ManabiSpokenAudioIntent] = [:]
    private static var appliedState = AppliedState.inactive

    static var configurationOverrideForTesting: ((ManabiSpokenAudioIntent) throws -> Void)?
    static var deactivationOverrideForTesting: (() throws -> Void)?
    static var activeLeaseCountForTesting: Int { activeLeases.count }

    public static func acquire(_ intent: ManabiSpokenAudioIntent) throws -> ManabiSpokenAudioSessionLease {
        let nextIntent = effectiveIntent(for: Array(activeLeases.values) + [intent])
        try transitionAppliedState(to: nextIntent)

        let lease = ManabiSpokenAudioSessionLease(id: UUID(), intent: intent)
        activeLeases[lease.id] = intent
        return lease
    }

    fileprivate static func release(id: UUID) throws {
        guard activeLeases[id] != nil else { return }

        var remainingLeases = activeLeases
        remainingLeases.removeValue(forKey: id)
        let nextIntent = effectiveIntent(for: remainingLeases.values)
        // Logical ownership ends regardless of whether the platform transition
        // succeeds. The separately tracked applied state makes the next operation
        // retry an uncertain configuration instead of retaining an abandoned lease.
        activeLeases = remainingLeases
        try transitionAppliedState(to: nextIntent)
    }

    private static func transitionAppliedState(
        to intent: ManabiSpokenAudioIntent?
    ) throws {
        let targetState = intent.map(AppliedState.configured) ?? .inactive
        guard appliedState != targetState else { return }
        do {
            if let intent {
                try configureAudioSession(for: intent)
            } else {
                try deactivateAudioSession()
            }
            appliedState = targetState
        } catch {
            appliedState = .unknown
            throw error
        }
    }

    static func resetForTesting() {
        activeLeases.removeAll()
        appliedState = .inactive
        configurationOverrideForTesting = nil
        deactivationOverrideForTesting = nil
    }

    private static func effectiveIntent<S: Sequence>(for intents: S) -> ManabiSpokenAudioIntent?
    where S.Element == ManabiSpokenAudioIntent {
        intents.max { $0.priority < $1.priority }
    }

    private static func configureAudioSession(for intent: ManabiSpokenAudioIntent) throws {
        if let configurationOverrideForTesting {
            try configurationOverrideForTesting(intent)
            return
        }
#if os(iOS)
        let options: AVAudioSession.CategoryOptions = switch intent {
        case .pronunciation:
            [.mixWithOthers]
        case .readAloud, .recordedAudio:
            [.interruptSpokenAudioAndMixWithOthers]
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: options)
        try session.setActive(true)
#endif
    }

    private static func deactivateAudioSession() throws {
        if let deactivationOverrideForTesting {
            try deactivationOverrideForTesting()
            return
        }
#if os(iOS)
        try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
#endif
    }
}
