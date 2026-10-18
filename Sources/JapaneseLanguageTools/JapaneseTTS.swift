import SwiftUI
import AudioToolbox
#if os(iOS)
import UIKit
#endif
import Speech
import AVFoundation
import Combine

struct JapanesePronunciationAudioDownloader {
    static let maximumAudioBytes = 4 * 1_024 * 1_024
    static let maximumAudioDurationSeconds = 60.0
    var download: (URL) async throws -> URL

    static let live = Self { url in
        guard allows(url: url) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.timeoutInterval = 15
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(
            for: request, delegate: JapanesePronunciationRedirectPolicy()
        )
        defer { bytes.task.cancel() }
        try validate(response: response)
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumAudioBytes else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
            if data.count.isMultiple(of: 65_536) { try Task.checkCancellation() }
        }
        try Task.checkCancellation()
        guard !data.isEmpty,
              response.expectedContentLength < 0 || response.expectedContentLength == Int64(data.count) else {
            throw URLError(.badServerResponse)
        }
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        do {
            try data.write(to: temporaryURL, options: .atomic)
            try validateAudioFile(at: temporaryURL)
            try Task.checkCancellation()
            return temporaryURL
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    static func allows(url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "manabi.io"
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
            && url.path.hasPrefix("/media/audio/tofugu/") && url.pathExtension.lowercased() == "mp3"
    }

    static func validate(response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let finalURL = response.url, allows(url: finalURL),
              ["audio/mpeg", "audio/mp3"].contains(response.mimeType?.lowercased() ?? ""),
              response.value(forHTTPHeaderField: "Content-Range") == nil,
              response.expectedContentLength != 0,
              response.expectedContentLength <= Int64(maximumAudioBytes) else {
            throw URLError(.badServerResponse)
        }
        if let declaredLength = response.value(forHTTPHeaderField: "Content-Length") {
            guard let count = Int64(declaredLength.trimmingCharacters(in: .whitespacesAndNewlines)),
                  count > 0, count <= Int64(maximumAudioBytes) else {
                throw URLError(.badServerResponse)
            }
        }
        if let encoding = response.value(forHTTPHeaderField: "Content-Encoding"),
           encoding.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "identity" {
            throw URLError(.badServerResponse)
        }
    }

    static func validateAudioFile(at url: URL) throws {
        let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
              let size = attributes.fileSize, size > 0, size <= maximumAudioBytes else {
            throw URLError(.badServerResponse)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 10) ?? Data()
        let hasID3Header = prefix.count >= 10 && prefix.starts(with: [0x49, 0x44, 0x33])
            && (2...4).contains(prefix[3])
        let hasMPEGFrame = prefix.count >= 4 && prefix[0] == 0xff && prefix[1] & 0xe0 == 0xe0
        guard hasID3Header || hasMPEGFrame else { throw URLError(.badServerResponse) }
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard file.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatMPEGLayer3,
              format.sampleRate.isFinite, format.sampleRate > 0, format.sampleRate <= 192_000,
              (1...2).contains(format.channelCount), file.length > 0,
              Double(file.length) / format.sampleRate <= maximumAudioDurationSeconds,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096) else {
            throw URLError(.badServerResponse)
        }
        var decodedFrames: Int64 = 0
        while true {
            try Task.checkCancellation()
            buffer.frameLength = 0
            try file.read(into: buffer, frameCount: 4_096)
            guard buffer.frameLength > 0 else { break }
            decodedFrames += Int64(buffer.frameLength)
            guard Double(decodedFrames) / format.sampleRate <= maximumAudioDurationSeconds else {
                throw URLError(.dataLengthExceedsMaximum)
            }
        }
        guard decodedFrames > 0 else { throw URLError(.badServerResponse) }
    }
}

private final class JapanesePronunciationRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(request.url.map(JapanesePronunciationAudioDownloader.allows(url:)) == true ? request : nil)
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
    @MainActor var pronunciationAudioCache = JapanesePronunciationAudioCache.shared
    @MainActor private var activePronunciationArtifact: (
        cache: JapanesePronunciationAudioCache, artifact: JapanesePronunciationAudioCache.Artifact
    )?

#if DEBUG
    @MainActor var pronunciationAudioURLResolver = TofuguAudioIndex.audioURL
    @MainActor var recordedAudioPlaybackOverride: ((URL, String, @escaping () -> Void, @escaping () -> Void, @escaping () -> Void) -> Void)?
    @MainActor var speechRequestCompletionOverride: (() -> Void)?
    @MainActor var pronunciationArtifactEvictionCompletionOverride: ((URL) -> Void)?
#endif
    
    enum JapaneseTTSError: Error {
        case audioFileDoesNotExist
    }
    
    @MainActor private lazy var player = AVPlayer()
    @MainActor private var playerItem: AVPlayerItem?
    @MainActor private var playerItemStatusCancellable: AnyCancellable?
    @MainActor private var playerItemCompletionCancellables = Set<AnyCancellable>()
    @MainActor private var shouldPlayOnceReady = false
    @MainActor private var audioSessionLease: ManabiSpokenAudioSessionLease?
    
    @MainActor private var activePronunciationPlaybackID: UUID?
    @MainActor private lazy var speechSynth: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        return synthesizer
    }()
    @MainActor private var activeUtterance: AVSpeechUtterance?
    @MainActor var synthesizedSpeechStartOverride: ((AVSpeechUtterance) -> Void)?
    
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
        activePronunciationArtifact = nil
        // Retire callback authority before stopping native playback: stop can enqueue
        // completion callbacks which must not release the next request's lease.
        activeUtterance = nil
        activePronunciationPlaybackID = nil
        playerItemStatusCancellable = nil
        playerItemCompletionCancellables.removeAll()
        shouldPlayOnceReady = false
        playerItem = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        speechSynth.stopSpeaking(at: .immediate)
        releaseAudioSession()
        isPlaying = false
        JapaneseTTS.unpauseTts()
    }

    @MainActor
    private func finishSpeechRequest(_ requestID: UUID) {
        guard activeSpeechRequestID == requestID else { return }
        activeSpeechRequestID = nil
        resetPronunciationPlayback()
        refreshIsEnabled()
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
        guard !text.isEmpty, acquireAudioSessionIfNeeded() else {
            finishSpeechRequest(requestID)
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = configuredSynthesizedJapaneseVoice()
        utterance.volume = 0.9
        activeUtterance = utterance
        isPlaying = true
        JapaneseTTS.temporarilyPauseTts()
        if let synthesizedSpeechStartOverride {
            synthesizedSpeechStartOverride(utterance)
        } else {
            speechSynth.speak(utterance)
        }
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
        
        releaseAudioSession()
        // From Apple docs: It's strongly recommended to set AVPlayer's property automaticallyWaitsToMinimizeStalling to false. Not doing so can lead to poor startup times for playback and poor recovery from stalls.
        player.automaticallyWaitsToMinimizeStalling = false
        
        let key = try JapanesePronunciationAudioCache.Key(
            expression: expression, readingKana: readingKana, sourceURL: remoteAudioURL
        )
        let cache = pronunciationAudioCache
        let cachedArtifact = try await cache.cachedArtifact(for: key)
        try Task.checkCancellation()
        guard activeSpeechRequestID == requestID else { throw CancellationError() }
        let artifact: JapanesePronunciationAudioCache.Artifact
        if let cachedArtifact {
            artifact = cachedArtifact
        } else {
            let temporaryURL = try await pronunciationAudioDownloader.download(remoteAudioURL)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            try Task.checkCancellation()
            guard activeSpeechRequestID == requestID else { throw CancellationError() }
            artifact = try await cache.install(from: temporaryURL, for: key)
        }
        try Task.checkCancellation()
        guard activeSpeechRequestID == requestID else { throw CancellationError() }
        activePronunciationArtifact = (cache, artifact)
        loadAndPlayAudio(url: artifact.url, readingKana: readingKana, requestID: requestID)
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
                        self.handlePronunciationAudioEvent(
                            .readyToPlay, url: url, readingKana: readingKana,
                            requestID: requestID, playbackID: playbackID, item: item
                        )
                    case .failed:
                        self.handlePronunciationAudioEvent(
                            .didFail, url: url, readingKana: readingKana,
                            requestID: requestID, playbackID: playbackID, item: item
                        )
                    default: break
                    }
                }
            }
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handlePronunciationAudioEvent(
                        .didFinish, url: url, readingKana: readingKana,
                        requestID: requestID, playbackID: playbackID, item: item
                    )
                }
            }
            .store(in: &playerItemCompletionCancellables)
        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handlePronunciationAudioEvent(
                        .didFail, url: url, readingKana: readingKana,
                        requestID: requestID, playbackID: playbackID, item: item
                    )
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
            guard acquireAudioSessionIfNeeded() else {
                finishSpeechRequest(requestID)
                return
            }
            JapaneseTTS.temporarilyPauseTts()
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
        evictFailedPronunciationArtifact(url: url)
        speakSynthesizedJapanese(text: hiraganaToKatakana(text: readingKana), requestID: requestID)
    }

    @MainActor
    private func evictFailedPronunciationArtifact(url: URL) {
        guard let owned = activePronunciationArtifact, owned.artifact.url == url else { return }
        activePronunciationArtifact = nil
        Task { @MainActor [weak self] in
            try? await owned.cache.evict(owned.artifact)
#if DEBUG
            self?.pronunciationArtifactEvictionCompletionOverride?(owned.artifact.url)
#endif
        }
    }

    @MainActor
    private func acquireAudioSessionIfNeeded() -> Bool {
        if audioSessionLease != nil { return true }
        do {
            audioSessionLease = try ManabiSpokenAudioSession.acquire(.pronunciation)
            return true
        } catch {
            return false
        }
    }

    @MainActor
    private func releaseAudioSession() {
        try? audioSessionLease?.release()
        audioSessionLease = nil
    }
    
}

extension JapaneseTTS: AVSpeechSynthesizerDelegate {
    enum SynthesizedUtteranceEvent {
        case paused
        case playing
        case finished
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        receiveSynthesizedUtteranceEvent(.paused, utterance: utterance)
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        receiveSynthesizedUtteranceEvent(.finished, utterance: utterance)
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        receiveSynthesizedUtteranceEvent(.playing, utterance: utterance)
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        receiveSynthesizedUtteranceEvent(.playing, utterance: utterance)
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        receiveSynthesizedUtteranceEvent(.finished, utterance: utterance)
    }

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        receiveSynthesizedUtteranceEvent(.playing, utterance: utterance)
    }

    private func receiveSynthesizedUtteranceEvent(
        _ event: SynthesizedUtteranceEvent,
        utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.handleSynthesizedUtteranceEvent(event, utterance: utterance)
        }
    }

    @MainActor
    func handleSynthesizedUtteranceEvent(
        _ event: SynthesizedUtteranceEvent,
        utterance: AVSpeechUtterance
    ) {
        guard activeUtterance === utterance,
              let requestID = activeSpeechRequestID else { return }
        switch event {
        case .paused:
            isPlaying = false
            JapaneseTTS.unpauseTts()
        case .playing:
            isPlaying = true
            JapaneseTTS.temporarilyPauseTts()
        case .finished:
            finishSpeechRequest(requestID)
        }
    }
}
