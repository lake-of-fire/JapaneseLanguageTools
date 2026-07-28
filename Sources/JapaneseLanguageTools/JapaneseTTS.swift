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
        let (temporaryURL, _) = try await URLSession.shared.download(from: url)
        return temporaryURL
    }
}

public enum ManabiSpokenAudioIntent: Equatable, Sendable {
    case readAloud
    case recordedAudio
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
    
    enum JapaneseTTSError: Error {
        case audioFileDoesNotExist
    }
    
    private lazy var player: AVPlayer = {
        let player = AVPlayer()
        NotificationCenter.default
            .publisher(for: NSNotification.Name.AVPlayerItemDidPlayToEndTime)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isPlaying = false
                    JapaneseTTS.unpauseTts()
                }
            }
            .store(in: &cancellables)
        return player
    }()
    private var playerItem: AVPlayerItem?
    private var playerItemStatusCancellable: AnyCancellable?
    private var shouldPlayOnceReady = false
    private var cancellables = Set<AnyCancellable>()
    
    private static let speechSynth = AVSpeechSynthesizer()
#if os(iOS)
    private static let pronunciationAudioSessionOptions: AVAudioSession.CategoryOptions = [.mixWithOthers]
#endif
    
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
        NotificationCenter.default
            .addObserver(
                self,
                selector: #selector(handleAvailableVoicesDidChange),
                name: AVSpeechSynthesizer.availableVoicesDidChangeNotification,
                object: nil
            )
        Task { @MainActor [weak self] in
            self?.refreshIsEnabled()
        }
    }

    @objc
    @MainActor
    private func handleAvailableVoicesDidChange() {
        synthesizedJapaneseVoice = nil
        hasResolvedSynthesizedJapaneseVoice = false
    }

    @discardableResult
    @MainActor
    private func refreshIsEnabled() -> Bool {
        let enabled = Self.ttsEnabled()
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
    
    private static func configAudioSession() {
#if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: pronunciationAudioSessionOptions)
            try session.setActive(true)
        } catch { }
#endif
    }
    
    @MainActor
    public func speakJapaneseIfUnmuted(expression: String, readingKana: String? = nil) async {
        guard refreshIsEnabled(), !Task.isCancelled else { return }
        speechRequestTask?.cancel()
        speechRequestTask = nil
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
        guard !Task.isCancelled, activeSpeechRequestID == requestID else { return }
        guard let readingKana = readingKana else {
            speakSynthesizedJapanese(text: hiraganaToKatakana(text: expression))
            return
        }
        do {
            try await playAudio(
                expression: expression,
                readingKana: readingKana,
                requestID: requestID
            )
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, activeSpeechRequestID == requestID else { return }
            speakSynthesizedJapanese(text: hiraganaToKatakana(text: readingKana))
        }
    }
    
    @MainActor
    private func speakSynthesizedJapanese(text: String) {
        //        debugPrint("# speakSynthesizedJapanese", text)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = configuredSynthesizedJapaneseVoice()
        utterance.volume = 0.9
        //        utterance.rate = 1.3
        JapaneseTTS.configAudioSession()
        JapaneseTTS.speechSynth.speak(utterance)
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
        guard let remoteAudioURL = TofuguAudioIndex.audioURL(
            term: expression,
            readingKana: readingKana
        ) else {
            throw JapaneseTTSError.audioFileDoesNotExist
        }
        
        refreshAudioSession(isPlaying: false)
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
        let playerItem = AVPlayerItem(url: url)
        self.playerItem = playerItem
        playerItemStatusCancellable = playerItem.publisher(for: \.status).receive(on: RunLoop.main).sink { [weak self] status in
            MainActor.assumeIsolated {
                guard self?.playerItem === playerItem,
                      self?.activeSpeechRequestID == requestID else { return }
                switch status {
                case .readyToPlay:
                    if self?.shouldPlayOnceReady ?? false {
                        self?.shouldPlayOnceReady = false
                        self?.play()
                    }
                case .failed:
                    self?.speakSynthesizedJapanese(text: readingKana)
                    self?.shouldPlayOnceReady = false
                default: break
                }
            }
        }
        player.replaceCurrentItem(with: playerItem)
        play()
        shouldPlayOnceReady = true
    }
    
    @MainActor
    private func play() {
        isPlaying = true
        JapaneseTTS.temporarilyPauseTts()
        refreshAudioSession(isPlaying: true)
        player.currentItem?.audioTimePitchAlgorithm = .timeDomain
        player.play()
    }
    
    private func refreshAudioSession(isPlaying: Bool) {
#if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            if isPlaying {
                try session.setCategory(.playback, mode: .spokenAudio, options: JapaneseTTS.pronunciationAudioSessionOptions)
                try session.setActive(true)
            } else {
                try session.setCategory(.ambient, mode: .spokenAudio, options: JapaneseTTS.pronunciationAudioSessionOptions)
                try session.setActive(false, options: [.notifyOthersOnDeactivation])
            }
        } catch { }
#endif
    }
    
}

extension JapaneseTTS: AVSpeechSynthesizerDelegate {
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isPlaying = false
            JapaneseTTS.unpauseTts()
        }
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isPlaying = false
            JapaneseTTS.unpauseTts()
        }
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isPlaying = true
        }
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isPlaying = true
        }
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            JapaneseTTS.unpauseTts()
            isPlaying = false
        }
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isPlaying = true
        }
    }
}
