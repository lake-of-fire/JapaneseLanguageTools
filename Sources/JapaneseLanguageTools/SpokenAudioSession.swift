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
        try ManabiSpokenAudioSession.release(id: id)
        isReleased = true
    }

    deinit {
        let id = id
        Task { @MainActor in
            try? ManabiSpokenAudioSession.release(id: id)
        }
    }
}

@MainActor
public enum ManabiSpokenAudioSession {
    private static var activeLeases: [UUID: ManabiSpokenAudioIntent] = [:]

    static var configurationOverrideForTesting: ((ManabiSpokenAudioIntent) throws -> Void)?
    static var deactivationOverrideForTesting: (() throws -> Void)?
    static var activeLeaseCountForTesting: Int { activeLeases.count }

    public static func acquire(_ intent: ManabiSpokenAudioIntent) throws -> ManabiSpokenAudioSessionLease {
        let currentIntent = effectiveIntent(for: activeLeases.values)
        let nextIntent = effectiveIntent(for: Array(activeLeases.values) + [intent])
        if currentIntent != nextIntent, let nextIntent {
            try configureAudioSession(for: nextIntent)
        }

        let lease = ManabiSpokenAudioSessionLease(id: UUID(), intent: intent)
        activeLeases[lease.id] = intent
        return lease
    }

    fileprivate static func release(id: UUID) throws {
        guard activeLeases[id] != nil else { return }

        let currentIntent = effectiveIntent(for: activeLeases.values)
        var remainingLeases = activeLeases
        remainingLeases.removeValue(forKey: id)
        let nextIntent = effectiveIntent(for: remainingLeases.values)

        if let nextIntent {
            if nextIntent != currentIntent {
                try configureAudioSession(for: nextIntent)
            }
        } else {
            try deactivateAudioSession()
        }
        activeLeases = remainingLeases
    }

    static func resetForTesting() {
        activeLeases.removeAll()
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
