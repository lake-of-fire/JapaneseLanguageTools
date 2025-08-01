import SwiftUI
#if os(iOS)
import Mute
#endif
import Speech
import Combine

public class JapaneseTTS: NSObject, ObservableObject {
    public static let shared = JapaneseTTS()
    
    @MainActor
    @Published public var isEnabled = false
    @MainActor
    @Published public var isPlaying = false
    
    private var isEnabledCheckTask: Task<Bool, Error>?
    
    enum JapaneseTTSError: Error {
        case audioFileDoesNotExist
    }
    
    private lazy var player: AVPlayer = {
        let player = AVPlayer()
        NotificationCenter.default
            .publisher(for: NSNotification.Name.AVPlayerItemDidPlayToEndTime)
            .sink { @MainActor [weak self] _ in
                self?.isPlaying = false
                JapaneseTTS.unpauseTts()
            }
            .store(in: &cancellables)
        return player
    }()
    private var playerItem: AVPlayerItem?
    private var shouldPlayOnceReady = false
    private var cancellables = Set<AnyCancellable>()
    
    private static let speechSynth = AVSpeechSynthesizer()
    
    // For Instagram-like behavior.
    static var wasDeviceMuteOverriddenByUnmutingTts = false
    
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
        return (!Mute.shared.isMute || wasDeviceMuteOverriddenByUnmutingTts) && getTtsEnabled() && !(ttsTemporarilyPaused ?? false)
#else
        return getTtsEnabled() && !UserDefaults.standard.bool(forKey: "ttsTemporarilyPaused")
#endif
    }
    
    public override init() {
        super.init()
        Task { [weak self] in
            await self?.refreshIsEnabled()
        }
    }
    
    //    deinit {
    //        isEnabledCheckTask?.cancel()
    //    }
    
    @MainActor
    private func refreshIsEnabled() async -> Bool {
        isEnabledCheckTask?.cancel()
        isEnabledCheckTask = Task { @MainActor [weak self] () -> Bool in
            try Task.checkCancellation()
            let toSet = Self.ttsEnabled()
            isEnabled = toSet
            return toSet
        }
        if let isEnabledCheckTask {
            do {
                return try await isEnabledCheckTask.value
            } catch {
                return false
            }
        }
        return false
    }
    
    /// Used for the user manually tapping to toggle, not for other programmatic manipulation.
    @MainActor
    public func toggleTts() async {
        let enabled = await refreshIsEnabled()
        
#if os(iOS)
        if enabled && Mute.shared.isMute {
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
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .interruptSpokenAudioAndMixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { }
#endif
    }
    
    @MainActor
    public func speakJapaneseIfUnmuted(expression: String, readingKana: String? = nil) async {
        guard await refreshIsEnabled() else { return }
        speakJapanese(expression: expression, readingKana: readingKana)
    }
    
    @MainActor
    public func speakJapanese(expression: String, readingKana: String? = nil) {
        guard let readingKana = readingKana else {
            speakSynthesizedJapanese(text: hiraganaToKatakana(text: expression))
            return
        }
        do {
            try playAudio(expression: expression, readingKana: readingKana)
        } catch {
            speakSynthesizedJapanese(text: hiraganaToKatakana(text: readingKana))
        }
    }
    
    private func speakSynthesizedJapanese(text: String) {
        //        debugPrint("# speakSynthesizedJapanese", text)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.volume = 0.9
        //        utterance.rate = 1.3
        JapaneseTTS.configAudioSession()
        JapaneseTTS.speechSynth.speak(utterance)
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
    private func playAudio(expression: String, readingKana: String) throws {
        guard TofuguAudioIndex.audioURL(term: expression, readingKana: readingKana) != nil else {
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
            loadAndPlayAudio(url: localAudioPath, readingKana: readingKana)
        } else {
            download(expression: expression, readingKana: readingKana, toPath: localAudioPath) { [weak self] audioPath in
                guard let audioPath = audioPath else {
                    self?.speakSynthesizedJapanese(text: readingKana)
                    return
                }
                self?.loadAndPlayAudio(url: audioPath, readingKana: readingKana)
            }
        }
    }
    
    @MainActor
    private func loadAndPlayAudio(url: URL, readingKana: String) {
        let playerItem = AVPlayerItem(url: url)
        self.playerItem = playerItem
        playerItem.publisher(for: \.status).receive(on: RunLoop.main).sink { @MainActor [weak self] status in
            switch playerItem.status {
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
        }.store(in: &cancellables)
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
            if isPlaying {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .interruptSpokenAudioAndMixWithOthers)
            } else {
                try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .spokenAudio, options: .interruptSpokenAudioAndMixWithOthers)
            }
            try AVAudioSession.sharedInstance().setActive(isPlaying)
        } catch { }
#endif
    }
    
    /// Expects hiragana fo rreadingKana
    private func download(expression: String, readingKana: String, toPath path: URL, completion: @escaping ((URL?) -> Void)) {
        guard let audioURL = TofuguAudioIndex.audioURL(term: expression, readingKana: readingKana) else {
            completion(nil)
            return
        }
        
        Task.detached {
            let task = URLSession.shared.downloadTask(with: audioURL) { localURL, urlResponse, error in
                guard let localURL = localURL else {
                    Task { @MainActor in
                        completion(nil)
                    }
                    return
                }
                do {
                    try FileManager.default.moveItem(at: localURL, to: path)
                } catch {
                    Task { @MainActor in
                        completion(nil)
                    }
                }
                
                Task { @MainActor in
                    completion(path)
                }
            }
            task.resume()
        }
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
