import SwiftUI
#if os(iOS)
import AudioToolbox
import UIKit
#endif
import Speech
import AVFoundation
import Combine

struct JapanesePronunciationAudioDownloader {
    var download: (URL) async throws -> URL

    static let live = Self { url in
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        try validate(response: response)
        return temporaryURL
    }

    static func validate(response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

public enum ManabiSpokenAudioIntent: Equatable, Sendable {
    case readAloud
    case recordedAudio
    case pronunciation
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

    deinit {
        guard !isReleased else { return }
        let id = id
        Task { @MainActor in
            try? ManabiSpokenAudioSession.release(id: id)
        }
    }

    public func release() throws {
        guard !isReleased else { return }
        defer { isReleased = true }
        try ManabiSpokenAudioSession.release(id: id)
    }
}

@MainActor
public enum ManabiSpokenAudioSession {
    private static var activeLeases: [UUID: ManabiSpokenAudioIntent] = [:]

#if DEBUG
    static var activationOverrideForTesting: ((ManabiSpokenAudioIntent) throws -> Void)?
    static var deactivationOverrideForTesting: (() throws -> Void)?
    static var activeLeaseCountForTesting: Int { activeLeases.count }

    static func resetForTesting() {
        activeLeases.removeAll()
        activationOverrideForTesting = nil
        deactivationOverrideForTesting = nil
    }
#endif

    public static func acquire(_ intent: ManabiSpokenAudioIntent) throws -> ManabiSpokenAudioSessionLease {
        if activeLeases.isEmpty {
#if DEBUG
            if let activationOverrideForTesting {
                try activationOverrideForTesting(intent)
            } else {
                try activateAudioSession()
            }
#else
            try activateAudioSession()
#endif
        }
        let lease = ManabiSpokenAudioSessionLease(id: UUID(), intent: intent)
        activeLeases[lease.id] = intent
        return lease
    }

    private static func activateAudioSession() throws {
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: .interruptSpokenAudioAndMixWithOthers)
        try session.setActive(true)
#endif
    }

    fileprivate static func release(id: UUID) throws {
        guard activeLeases[id] != nil else { return }
        let wasFinalLease = activeLeases.count == 1
        activeLeases.removeValue(forKey: id)
        guard wasFinalLease else { return }
#if DEBUG
        if let deactivationOverrideForTesting {
            try deactivationOverrideForTesting()
        } else {
            try deactivateAudioSession()
        }
#else
        try deactivateAudioSession()
#endif
    }

    private static func deactivateAudioSession() throws {
#if os(iOS)
        try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
#endif
    }
}

#if os(iOS)
@MainActor
private final class SafeSilentSwitchDetector {
    static let shared = SafeSilentSwitchDetector()

    private(set) var isMute = false
    private var isAvailable = false
    private var isPlaying = false
    private var isScheduled = false
    private var isPaused = false
    private var interval: TimeInterval = 0
    private var soundID: SystemSoundID = 0
    private let checkInterval: TimeInterval = 1.0

    private init() {
        guard let soundURL = Self.muteSoundURL() else {
            isAvailable = false
            return
        }

        var createdSoundID: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(soundURL as CFURL, &createdSoundID) == kAudioServicesNoError else {
            isAvailable = false
            return
        }

        soundID = createdSoundID
        isAvailable = true

        var yes: UInt32 = 1
        AudioServicesSetProperty(
            kAudioServicesPropertyIsUISound,
            UInt32(MemoryLayout.size(ofValue: soundID)),
            &soundID,
            UInt32(MemoryLayout.size(ofValue: yes)),
            &yes
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        schedulePlaySound()
    }

    deinit {
        if soundID != 0 {
            AudioServicesDisposeSystemSoundID(soundID)
        }
        NotificationCenter.default.removeObserver(self)
    }

    private static func muteSoundURL() -> URL? {
        var candidates = [URL?]()

        candidates.append(Bundle.main.url(forResource: "mute", withExtension: "aiff"))

        let bundleNames = ["Mute", "Mute_Mute"]
        let searchRoots: [URL?] = [
            Bundle.main.resourceURL,
            Bundle.main.privateFrameworksURL,
            Bundle.main.bundleURL.appendingPathComponent("Frameworks"),
            Bundle.main.bundleURL,
        ]

        for root in searchRoots {
            candidates.append(root?.appendingPathComponent("Mute.framework/mute.aiff"))
            for bundleName in bundleNames {
                candidates.append(root?.appendingPathComponent("\(bundleName).bundle/mute.aiff"))
                candidates.append(root?.appendingPathComponent("Mute.framework/\(bundleName).bundle/mute.aiff"))
            }
        }

        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    @objc private func didEnterBackground() {
        isPaused = true
    }

    @objc private func willEnterForeground() {
        isPaused = false
        if !isPlaying {
            schedulePlaySound()
        }
    }

    private func schedulePlaySound() {
        guard isAvailable, !isScheduled else { return }
        isScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + checkInterval) { [weak self] in
            guard let self else { return }
            self.isScheduled = false
            guard !self.isPaused else { return }
            self.playSound()
        }
    }

    private func playSound() {
        guard isAvailable, !isPaused, !isPlaying else { return }
        interval = Date.timeIntervalSinceReferenceDate
        isPlaying = true
        AudioServicesPlaySystemSoundWithCompletion(soundID) { [weak self] in
            Task { @MainActor in
                self?.soundFinishedPlaying()
            }
        }
    }

    private func soundFinishedPlaying() {
        isPlaying = false
        let elapsed = Date.timeIntervalSinceReferenceDate - interval
        isMute = elapsed < 0.1
        schedulePlaySound()
    }
}
#endif

public class JapaneseTTS: NSObject, ObservableObject {
    public static let shared = JapaneseTTS()
    
    @MainActor
    @Published public var isEnabled = false
    @MainActor
    @Published public var isPlaying = false
    
    @MainActor
    private var speechRequestTask: Task<Void, Never>?
    @MainActor
    private var activeSpeechRequestID: UUID?
    @MainActor
    private var synthesizedJapaneseVoice: AVSpeechSynthesisVoice?
    @MainActor
    private var hasResolvedSynthesizedJapaneseVoice = false

    var pronunciationAudioDownloader = JapanesePronunciationAudioDownloader.live

#if DEBUG
    // Tests inject deterministic playback events so request ownership can be
    // exercised without media hardware.
    @MainActor var pronunciationAudioURLResolver = TofuguAudioIndex.audioURL
    @MainActor var recordedAudioPlaybackOverride: ((URL, String, @escaping () -> Void, @escaping () -> Void, @escaping () -> Void) -> Void)?
    @MainActor var synthesizedSpeechStartOverride: ((AVSpeechUtterance) -> Void)?
    @MainActor var speechRequestCompletionOverride: (() -> Void)?
#endif
    
    enum JapaneseTTSError: Error {
        case audioFileDoesNotExist
    }
    
    @MainActor private lazy var player = AVPlayer()
    @MainActor private var playerItem: AVPlayerItem?
    @MainActor private var playerItemStatusCancellable: AnyCancellable?
    @MainActor private var playerItemCompletionCancellables = Set<AnyCancellable>()
    @MainActor private var shouldPlayOnceReady = false
    @MainActor private var activePronunciationPlaybackID: UUID?
    @MainActor private var activeUtterance: AVSpeechUtterance?
    @MainActor private var pronunciationSessionLease: ManabiSpokenAudioSessionLease?
    @MainActor private lazy var speechSynth: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        return synthesizer
    }()

    // For Instagram-like behavior.
    private static var wasDeviceMuteOverriddenByUnmutingTts = false

    @MainActor
    private class func getTtsEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: "ttsEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "ttsEnabled")
            return true
        }
        return UserDefaults.standard.bool(forKey: "ttsEnabled")
    }
    
    @MainActor
    private class func ttsEnabled() -> Bool {
        let ttsTemporarilyPaused = UserDefaults.standard.object(forKey: "ttsTemporarilyPaused") as? Bool
        if ttsTemporarilyPaused == nil {
            UserDefaults.standard.set(false, forKey: "ttsTemporarilyPaused")
        }
#if targetEnvironment(simulator)
        return false
#elseif os(iOS)
        return (!SafeSilentSwitchDetector.shared.isMute || wasDeviceMuteOverriddenByUnmutingTts) && getTtsEnabled() && !(ttsTemporarilyPaused ?? false)
#else
        return getTtsEnabled() && !UserDefaults.standard.bool(forKey: "ttsTemporarilyPaused")
#endif
    }
    
    public override init() {
        super.init()
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            NotificationCenter.default
                .addObserver(
                    self,
                    selector: #selector(handleAvailableVoicesDidChange),
                    name: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
                    object: nil
                )
        }
        Task { @MainActor [weak self] in
            self?.refreshIsEnabled()
        }
    }

    @objc nonisolated
    private func handleAvailableVoicesDidChange() {
        Task { @MainActor [weak self] in
            self?.synthesizedJapaneseVoice = nil
            self?.hasResolvedSynthesizedJapaneseVoice = false
        }
    }

    @discardableResult
    @MainActor
    private func refreshIsEnabled() -> Bool {
        let enabled = Self.ttsEnabled() && !isPlaying
        isEnabled = enabled
        return enabled
    }
    
    /// Used for the user manually tapping to toggle, not for other programmatic manipulation.
    @MainActor
    public func toggleTts() async {
        let enabled = refreshIsEnabled()

#if os(iOS)
        if enabled && SafeSilentSwitchDetector.shared.isMute {
            Self.wasDeviceMuteOverriddenByUnmutingTts = true
        }
#endif
        
        if enabled {
            Self.unpauseTts()
        }
        
        isEnabled = Self.ttsEnabled()
    }
    
//    public class func muteTts() {
//        UserDefaults.standard.set(false, forKey: "ttsEnabled")
//    }
//    
//    public class func unmuteTts() {
//        UserDefaults.standard.set(false, forKey: "ttsEnabled")
//    }
    
    public static func temporarilyPauseTts() {
        UserDefaults.standard.set(true, forKey: "ttsTemporarilyPaused")
    }
    
    public static func unpauseTts() {
        UserDefaults.standard.set(false, forKey: "ttsTemporarilyPaused")
    }
    
    @MainActor
    private func resetPronunciationPlayback() {
        playerItemStatusCancellable = nil
        playerItemCompletionCancellables.removeAll()
        shouldPlayOnceReady = false
        activePronunciationPlaybackID = nil
        playerItem = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        activeUtterance = nil
        speechSynth.stopSpeaking(at: .immediate)
        isPlaying = false
        try? pronunciationSessionLease?.release()
        pronunciationSessionLease = nil
    }

    @MainActor
    private func finishSpeechRequest(_ requestID: UUID) {
        guard activeSpeechRequestID == requestID else { return }
        activeSpeechRequestID = nil
        resetPronunciationPlayback()
        refreshIsEnabled()
    }

    @MainActor
    private func acquirePronunciationSession() {
        if pronunciationSessionLease == nil {
            pronunciationSessionLease = try? ManabiSpokenAudioSession.acquire(.pronunciation)
        }
    }

    @MainActor
    public func speakJapaneseIfUnmuted(expression: String, readingKana: String? = nil) async {
        guard refreshIsEnabled(), !Task.isCancelled else { return }
        speechRequestTask?.cancel()
        speechRequestTask = nil
        resetPronunciationPlayback()
        let requestID = UUID()
        activeSpeechRequestID = requestID
        await performSpeakJapanese(
            expression: expression,
            readingKana: readingKana,
            requestID: requestID
        )
    }
    
    @MainActor
    public func speakJapanese(expression: String, readingKana: String? = nil) {
        speechRequestTask?.cancel()
        resetPronunciationPlayback()
        let requestID = UUID()
        activeSpeechRequestID = requestID
        speechRequestTask = Task { @MainActor [weak self] in
            await self?.performSpeakJapanese(
                expression: expression,
                readingKana: readingKana,
                requestID: requestID
            )
        }
    }

    @MainActor
    private func performSpeakJapanese(
        expression: String,
        readingKana: String?,
        requestID: UUID
    ) async {
        defer {
#if DEBUG
            speechRequestCompletionOverride?()
#endif
        }
        guard !Task.isCancelled, activeSpeechRequestID == requestID else { return }
        guard let readingKana = readingKana else {
            speakSynthesizedJapanese(text: hiraganaToKatakana(text: expression), requestID: requestID)
            return
        }
        do {
            try await playAudio(
                expression: expression,
                readingKana: readingKana,
                requestID: requestID
            )
        } catch is CancellationError {
            finishSpeechRequest(requestID)
            return
        } catch {
            guard !Task.isCancelled, activeSpeechRequestID == requestID else { return }
            speakSynthesizedJapanese(text: hiraganaToKatakana(text: readingKana), requestID: requestID)
        }
    }
    
    @MainActor
    private func speakSynthesizedJapanese(text: String, requestID: UUID) {
        guard activeSpeechRequestID == requestID else { return }
        resetPronunciationPlayback()
        guard !text.isEmpty else {
            finishSpeechRequest(requestID)
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = configuredSynthesizedJapaneseVoice()
        utterance.volume = 0.9
        activeUtterance = utterance
        acquirePronunciationSession()
        isPlaying = true
#if DEBUG
        if let synthesizedSpeechStartOverride {
            synthesizedSpeechStartOverride(utterance)
        } else {
            speechSynth.speak(utterance)
        }
#else
        speechSynth.speak(utterance)
#endif
    }

    @MainActor
    private func configuredSynthesizedJapaneseVoice() -> AVSpeechSynthesisVoice? {
        if !hasResolvedSynthesizedJapaneseVoice {
            synthesizedJapaneseVoice = AVSpeechSynthesisVoice(language: "ja-JP")
            hasResolvedSynthesizedJapaneseVoice = true
        }
        return synthesizedJapaneseVoice
    }
    
    /// Helper: katakana is pronounced more accurately for words.
    private func hiraganaToKatakana(text: String) -> String {
        let kanaMutableString = NSMutableString(string: text) as CFMutableString
        CFStringTransform(kanaMutableString, nil, kCFStringTransformHiraganaKatakana, false)
        var kanaString = kanaMutableString as String
        for (from, to) in JapaneseTTS.katakanaTransforms {
            kanaString = kanaString.replacingOccurrences(of: from, with: to)
        }
        return kanaString
    }
    
    static private let katakanaTransforms: [(String, String)] = [
        ("アア", "アー"), ("カア", "カー"), ("ガア", "ガー"), ("サア", "サー"), ("ザア", "ザー"), ("タア", "ター"), ("ダア", "ダー"), ("ハア", "ハー"), ("パア", "パー"), ("バア", "バー"), ("マア", "マー"), ("ヤア", "ヤー"), ("ラア", "ラー"), ("ワア", "ワー"), ("イイ", "イー"), ("キイ", "キー"), ("ギイ", "ギー"), ("シイ", "シー"), ("ジイ", "ジー"), ("チイ", "チー"), ("ヂイ", "ヂー"), ("ニイ", "ニー"), ("ヒイ", "ヒー"), ("ピイ", "ピー"), ("ビイ", "ビー"), ("ミイ", "ミー"), ("リイ", "リー"), ("クウ", "クー"), ("グウ", "グー"), ("スウ", "スー"), ("ズウ", "ズー"), ("ツウ", "ツー"), ("ヅウ", "ヅー"), ("ヌウ", "ヌー"), ("フウ", "フー"), ("プウ", "プー"), ("ブウ", "ブー"), ("ムウ", "ムー"), ("ユウ", "ユー"), ("ルウ", "ルー"), ("エイ", "エー"), ("ケイ", "ケー"), ("ゲイ", "ゲー"), ("セイ", "セー"), ("ゼイ", "ゼー"), ("テイ", "テー"), ("デイ", "デー"), ("ネイ", "ネー"), ("ネエ", "ネー"), ("ヘイ", "ヘー"), ("ペイ", "ペー"), ("ベイ", "ベー"), ("メイ", "メー"), ("レイ", "レー"), ("オウ", "オー"), ("コウ", "コー"), ("ゴウ", "ゴー"), ("ソウ", "ソー"), ("ゾウ", "ゾー"), ("トウ", "トー"), ("トオ", "トー"), ("ドウ", "ドー"), ("ドオ", "ドー"), ("ノウ", "ノー"), ("ホウ", "ホー"), ("ポウ", "ポー"), ("ボウ", "ボー"), ("モウ", "モー"), ("ヨウ", "ヨー"), ("ロウ", "ロー"), ("キャア", "キャー"), ("ギャア", "ギャー"), ("チャア", "チャー"), ("ヂャア", "ヂャー"), ("ニャア", "ニャー"), ("ヒャア", "ヒャー"), ("ピャア", "ピャー"), ("ビャア", "ビャー"), ("ミャア", "ミャー"), ("リャア", "リャー"), ("キュウ", "キュー"), ("ギュウ", "ギュー"), ("シュウ", "シュー"), ("ジュウ", "ジュー"), ("チュウ", "チュー"), ("ヂュウ", "ヂュー"), ("ニュウ", "ニュー"), ("ヒュウ", "ヒュー"), ("ピュウ", "ピュー"), ("ビュウ", "ビュー"), ("ミュウ", "ミュー"), ("リュウ", "リュー"), ("キョウ", "キョー"), ("ギョウ", "ギョー"), ("ショウ", "ショー"), ("ジョウ", "ジョー"), ("チョウ", "チョー"), ("ヂョウ", "ヂョー"), ("ニョウ", "ニョー"), ("ヒョウ", "ヒョー"), ("ピョウ", "ピョー"), ("ビョウ", "ビョー"), ("ミョウ", "ミョー"), ("リョウ", "リョー"),
    ]
}

extension JapaneseTTS {
    // MARK: Audio player
    
    @MainActor
    private func playAudio(
        expression: String,
        readingKana: String,
        requestID: UUID
    ) async throws {
#if DEBUG
        let remoteAudioURL = pronunciationAudioURLResolver(expression, readingKana)
#else
        let remoteAudioURL = TofuguAudioIndex.audioURL(term: expression, readingKana: readingKana)
#endif
        guard let remoteAudioURL else {
            throw JapaneseTTSError.audioFileDoesNotExist
        }
        
        // From Apple docs: It's strongly recommended to set AVPlayer's property automaticallyWaitsToMinimizeStalling to false. Not doing so can lead to poor startup times for playback and poor recovery from stalls.
        player.automaticallyWaitsToMinimizeStalling = false
        
        let filename = "\(expression)【\(readingKana)】.mp3"
        let cacheDirectory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let audioDirectory = cacheDirectory.appendingPathComponent("audio").appendingPathComponent("tofugu")
        if (try? !audioDirectory.checkResourceIsReachable()) ?? true {
            try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        let localAudioPath = audioDirectory.appendingPathComponent(filename)
        
        if (try? localAudioPath.checkResourceIsReachable()) ?? false {
            guard activeSpeechRequestID == requestID else { throw CancellationError() }
            loadAndPlayAudio(url: localAudioPath, readingKana: readingKana, requestID: requestID)
        } else {
            let temporaryURL = try await pronunciationAudioDownloader.download(remoteAudioURL)
            try Task.checkCancellation()
            guard activeSpeechRequestID == requestID else { throw CancellationError() }
            if !FileManager.default.fileExists(atPath: localAudioPath.path) {
                do {
                    try FileManager.default.moveItem(at: temporaryURL, to: localAudioPath)
                } catch {
                    guard FileManager.default.fileExists(atPath: localAudioPath.path) else {
                        throw error
                    }
                }
            }
            try Task.checkCancellation()
            guard activeSpeechRequestID == requestID else { throw CancellationError() }
            loadAndPlayAudio(url: localAudioPath, readingKana: readingKana, requestID: requestID)
        }
    }
    
    @MainActor
    private func loadAndPlayAudio(url: URL, readingKana: String, requestID: UUID) {
        guard activeSpeechRequestID == requestID else { return }
        let playbackID = UUID()
        activePronunciationPlaybackID = playbackID
        shouldPlayOnceReady = true
#if DEBUG
        if let recordedAudioPlaybackOverride {
            isPlaying = true
            recordedAudioPlaybackOverride(
                url,
                readingKana,
                { [weak self] in
                    guard let self else { return }
                    self.handlePronunciationAudioEvent(
                        .readyToPlay,
                        url: url,
                        readingKana: readingKana,
                        requestID: requestID,
                        playbackID: playbackID
                    )
                },
                { [weak self] in
                    guard let self else { return }
                    self.handlePronunciationAudioEvent(
                        .didFinish,
                        url: url,
                        readingKana: readingKana,
                        requestID: requestID,
                        playbackID: playbackID
                    )
                },
                { [weak self] in
                    guard let self else { return }
                    self.handlePronunciationAudioEvent(
                        .didFail,
                        url: url,
                        readingKana: readingKana,
                        requestID: requestID,
                        playbackID: playbackID
                    )
                }
            )
            return
        }
#endif
        let item = AVPlayerItem(url: url)
        playerItem = item
        isPlaying = true
        playerItemStatusCancellable = item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch status {
                    case .readyToPlay:
                        self.handlePronunciationAudioEvent(.readyToPlay, url: url, readingKana: readingKana, requestID: requestID, playbackID: playbackID, item: item)
                    case .failed:
                        self.handlePronunciationAudioEvent(.didFail, url: url, readingKana: readingKana, requestID: requestID, playbackID: playbackID, item: item)
                    default: break
                    }
                }
            }
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handlePronunciationAudioEvent(.didFinish, url: url, readingKana: readingKana, requestID: requestID, playbackID: playbackID, item: item)
                }
            }
            .store(in: &playerItemCompletionCancellables)
        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handlePronunciationAudioEvent(.didFail, url: url, readingKana: readingKana, requestID: requestID, playbackID: playbackID, item: item)
                }
            }
            .store(in: &playerItemCompletionCancellables)
        player.replaceCurrentItem(with: item)
    }

    private enum PronunciationAudioEvent {
        case readyToPlay
        case didFinish
        case didFail
    }

    @MainActor
    private func handlePronunciationAudioEvent(
        _ event: PronunciationAudioEvent,
        url: URL,
        readingKana: String,
        requestID: UUID,
        playbackID: UUID,
        item: AVPlayerItem? = nil
    ) {
        guard activeSpeechRequestID == requestID,
              activePronunciationPlaybackID == playbackID,
              item == nil || playerItem === item else { return }

        switch event {
        case .readyToPlay:
            guard shouldPlayOnceReady else { return }
            shouldPlayOnceReady = false
            acquirePronunciationSession()
            if let item {
                item.audioTimePitchAlgorithm = .timeDomain
                player.play()
            }
        case .didFinish:
            finishSpeechRequest(requestID)
        case .didFail:
            failedPronunciationAudio(url: url, readingKana: readingKana, requestID: requestID)
        }
    }

    @MainActor
    private func failedPronunciationAudio(url: URL, readingKana: String, requestID: UUID) {
        guard activeSpeechRequestID == requestID else { return }
        // These are our derived audio-cache bytes, never user-owned content.
        // A failed cached item must not poison every future pronunciation.
        try? FileManager.default.removeItem(at: url)
        speakSynthesizedJapanese(text: hiraganaToKatakana(text: readingKana), requestID: requestID)
    }
}

extension JapaneseTTS: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishSynthesizedUtterance(utterance)
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishSynthesizedUtterance(utterance)
    }

    private func finishSynthesizedUtterance(_ utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.handleSynthesizedUtteranceEvent(utterance)
        }
    }

    @MainActor
    func handleSynthesizedUtteranceEvent(_ utterance: AVSpeechUtterance) {
        guard activeUtterance === utterance,
              let requestID = activeSpeechRequestID else { return }
        finishSpeechRequest(requestID)
    }
}
