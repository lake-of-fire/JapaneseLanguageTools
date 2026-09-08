import XCTest
import AVFoundation
@testable import JapaneseLanguageTools

final class JapaneseLanguageToolsTests: XCTestCase {
    func testDigitsOnlyIsConsistentAcrossStringProtocolDispatch() {
        func generic<S: StringProtocol>(_ value: S) -> Bool {
            value.isASCIIOrFullWidthDigitsOnly
        }
        for (value, expected) in [("", false), ("123", true), ("１２３", true), ("1２3", true), ("1猫", false)] {
            XCTAssertEqual(value.isASCIIOrFullWidthDigitsOnly, expected)
            XCTAssertEqual(value[...].isASCIIOrFullWidthDigitsOnly, expected)
            XCTAssertEqual(generic(value), expected)
        }
    }

    func testPronunciationDownloadRejectsHTTPErrorBodies() throws {
        let url = URL(string: "https://example.com/audio.mp3")!
        for status in [200, 206] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            XCTAssertNoThrow(try JapanesePronunciationAudioDownloader.validate(response: response))
        }
        for status in [301, 404, 429, 500] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            XCTAssertThrowsError(try JapanesePronunciationAudioDownloader.validate(response: response))
        }
        XCTAssertThrowsError(try JapanesePronunciationAudioDownloader.validate(
            response: URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        ))
    }

    @MainActor
    func testFailedRecordedPronunciationEvictsCacheAndFallsBackToSynthesis() async throws {
        ManabiSpokenAudioSession.resetForTesting()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        configureAudioSessionForTesting()

        let expression = "recorded-failure-\(UUID().uuidString)"
        let reading = "よみ"
        let remoteURL = URL(string: "https://example.com/\(expression).mp3")!
        let downloadedURL = try makeTemporaryAudioFile()
        let cachedURL = try pronunciationCacheURL(expression: expression, reading: reading)
        defer { try? FileManager.default.removeItem(at: cachedURL) }
        let tts = JapaneseTTS()
        var recordedReady: (() -> Void)?
        var recordedFailure: (() -> Void)?
        var synthesizedUtterance: AVSpeechUtterance?
        let recordedPlaybackStarted = expectation(description: "recorded playback started")
        let speechFinished = expectation(description: "synthesized speech finished")
        tts.pronunciationAudioURLResolver = { _, _ in remoteURL }
        tts.pronunciationAudioDownloader = .init { _ in downloadedURL }
        tts.recordedAudioPlaybackOverride = { _, _, ready, _, failed in
            recordedReady = ready
            recordedFailure = failed
            recordedPlaybackStarted.fulfill()
        }
        tts.synthesizedSpeechStartOverride = { utterance in synthesizedUtterance = utterance }

        tts.speakJapanese(expression: expression, readingKana: reading)
        await fulfillment(of: [recordedPlaybackStarted], timeout: 1)

        XCTAssertTrue(FileManager.default.fileExists(atPath: cachedURL.path))
        try XCTUnwrap(recordedReady)()
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
        XCTAssertNotNil(recordedFailure)
        recordedFailure?()

        XCTAssertFalse(FileManager.default.fileExists(atPath: cachedURL.path))
        XCTAssertEqual(synthesizedUtterance?.speechString, "ヨミ")
        XCTAssertTrue(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)

        ManabiSpokenAudioSession.deactivationOverrideForTesting = { speechFinished.fulfill() }
        tts.speechSynthesizer(AVSpeechSynthesizer(), didFinish: try XCTUnwrap(synthesizedUtterance))
        await fulfillment(of: [speechFinished], timeout: 1)
        XCTAssertFalse(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
    }

    @MainActor
    func testSupersededDownloadAndRecordedCompletionCannotFinishReplacement() async throws {
        ManabiSpokenAudioSession.resetForTesting()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        configureAudioSessionForTesting()

        let firstExpression = "superseded-download-\(UUID().uuidString)"
        let firstDownloadedURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: firstDownloadedURL) }
        let secondExpression = "superseded-player-\(UUID().uuidString)"
        let secondDownloadedURL = try makeTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: secondDownloadedURL) }
        let secondCachedURL = try pronunciationCacheURL(expression: secondExpression, reading: "よみ")
        defer { try? FileManager.default.removeItem(at: secondCachedURL) }
        let tts = JapaneseTTS()
        var resumeFirstDownload: CheckedContinuation<URL, Error>?
        var recordedReady: (() -> Void)?
        var recordedCompletion: (() -> Void)?
        var recordedFailure: (() -> Void)?
        var synthesizedUtterances = [AVSpeechUtterance]()
        let firstDownloadStarted = expectation(description: "first download started")
        let replacementStarted = expectation(description: "replacement synthesis started")
        let recordedPlaybackStarted = expectation(description: "recorded playback started")
        let finalReplacementStarted = expectation(description: "final replacement synthesis started")
        let finalReplacementFinished = expectation(description: "final replacement synthesis finished")
        tts.pronunciationAudioURLResolver = { expression, _ in
            URL(string: "https://example.com/\(expression).mp3")
        }
        tts.pronunciationAudioDownloader = .init { _ in
            try await withCheckedThrowingContinuation { continuation in
                resumeFirstDownload = continuation
                firstDownloadStarted.fulfill()
            }
        }
        tts.recordedAudioPlaybackOverride = { _, _, ready, finished, failed in
            recordedReady = ready
            recordedCompletion = finished
            recordedFailure = failed
            recordedPlaybackStarted.fulfill()
        }
        tts.synthesizedSpeechStartOverride = { utterance in
            synthesizedUtterances.append(utterance)
            if synthesizedUtterances.count == 1 {
                replacementStarted.fulfill()
            } else {
                finalReplacementStarted.fulfill()
            }
        }

        tts.speakJapanese(expression: firstExpression, readingKana: "よみ")
        await fulfillment(of: [firstDownloadStarted], timeout: 1)
        tts.speakJapanese(expression: "replacement", readingKana: nil)
        await fulfillment(of: [replacementStarted], timeout: 1)
        let replacementUtterance = try XCTUnwrap(synthesizedUtterances.last)

        let supersededDownloadFinished = expectation(description: "superseded download request finished")
        tts.speechRequestCompletionOverride = { supersededDownloadFinished.fulfill() }
        try XCTUnwrap(resumeFirstDownload).resume(returning: firstDownloadedURL)
        await fulfillment(of: [supersededDownloadFinished], timeout: 1)
        tts.speechRequestCompletionOverride = nil
        XCTAssertNil(recordedCompletion)
        XCTAssertTrue(tts.isPlaying)

        // Exercise the same request fence after an old player has already started.
        tts.pronunciationAudioDownloader = .init { _ in secondDownloadedURL }
        tts.speakJapanese(expression: secondExpression, readingKana: "よみ")
        await fulfillment(of: [recordedPlaybackStarted], timeout: 1)
        try XCTUnwrap(recordedReady)()
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
        let oldRecordedCompletion = try XCTUnwrap(recordedCompletion)
        let oldRecordedFailure = try XCTUnwrap(recordedFailure)
        tts.speakJapanese(expression: "replacement-again", readingKana: nil)
        await fulfillment(of: [finalReplacementStarted], timeout: 1)
        let finalUtterance = try XCTUnwrap(synthesizedUtterances.last)

        oldRecordedCompletion()
        oldRecordedFailure()
        XCTAssertTrue(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
        ManabiSpokenAudioSession.deactivationOverrideForTesting = { finalReplacementFinished.fulfill() }
        tts.speechSynthesizer(AVSpeechSynthesizer(), didFinish: finalUtterance)
        await fulfillment(of: [finalReplacementFinished], timeout: 1)
        XCTAssertFalse(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
        XCTAssertFalse(replacementUtterance === finalUtterance)
    }

    @MainActor
    func testObsoleteSynthesizedFinishAndCancelDoNotReleaseCurrentRequestLease() async throws {
        ManabiSpokenAudioSession.resetForTesting()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        configureAudioSessionForTesting()

        let tts = JapaneseTTS()
        var utterances = [AVSpeechUtterance]()
        let firstStarted = expectation(description: "first synthesis started")
        let secondStarted = expectation(description: "second synthesis started")
        let secondFinished = expectation(description: "second synthesis finished")
        tts.synthesizedSpeechStartOverride = { utterance in
            utterances.append(utterance)
            if utterances.count == 1 {
                firstStarted.fulfill()
            } else {
                secondStarted.fulfill()
            }
        }

        tts.speakJapanese(expression: "first", readingKana: nil)
        await fulfillment(of: [firstStarted], timeout: 1)
        let first = try XCTUnwrap(utterances.last)
        tts.speakJapanese(expression: "second", readingKana: nil)
        await fulfillment(of: [secondStarted], timeout: 1)
        let second = try XCTUnwrap(utterances.last)

        tts.handleSynthesizedUtteranceEvent(first)
        tts.handleSynthesizedUtteranceEvent(first)
        XCTAssertTrue(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)

        ManabiSpokenAudioSession.deactivationOverrideForTesting = { secondFinished.fulfill() }
        tts.speechSynthesizer(AVSpeechSynthesizer(), didCancel: second)
        await fulfillment(of: [secondFinished], timeout: 1)
        XCTAssertFalse(tts.isPlaying)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
    }

    @MainActor
    func testRecordedReadyAndFinishAcquireAndReleaseExactlyOneLease() async throws {
        ManabiSpokenAudioSession.resetForTesting()
        defer { ManabiSpokenAudioSession.resetForTesting() }
        var activations = 0
        var deactivations = 0
        ManabiSpokenAudioSession.activationOverrideForTesting = { _ in activations += 1 }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = { deactivations += 1 }
        let expression = "recorded-success-\(UUID().uuidString)"
        let downloaded = try makeTemporaryAudioFile()
        let cached = try pronunciationCacheURL(expression: expression, reading: "よみ")
        defer {
            try? FileManager.default.removeItem(at: downloaded)
            try? FileManager.default.removeItem(at: cached)
        }
        let tts = JapaneseTTS()
        let started = expectation(description: "recorded item loaded")
        var ready: (() -> Void)?
        var finished: (() -> Void)?
        tts.pronunciationAudioURLResolver = { _, _ in URL(string: "https://example.com/audio.mp3") }
        tts.pronunciationAudioDownloader = .init { _ in downloaded }
        tts.recordedAudioPlaybackOverride = { _, _, onReady, onFinish, _ in
            ready = onReady
            finished = onFinish
            started.fulfill()
        }
        tts.speakJapanese(expression: expression, readingKana: "よみ")
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
        try XCTUnwrap(ready)()
        try XCTUnwrap(ready)()
        XCTAssertTrue(tts.isPlaying)
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 1)
        try XCTUnwrap(finished)()
        try XCTUnwrap(finished)()
        try XCTUnwrap(ready)()
        XCTAssertFalse(tts.isPlaying)
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(deactivations, 1)
        XCTAssertEqual(ManabiSpokenAudioSession.activeLeaseCountForTesting, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cached.path))
    }

    private func makeTemporaryAudioFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")
        try Data([0]).write(to: url)
        return url
    }

    private func pronunciationCacheURL(expression: String, reading: String) throws -> URL {
        let directory = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return directory
            .appendingPathComponent("audio")
            .appendingPathComponent("tofugu")
            .appendingPathComponent("\(expression)【\(reading)】.mp3")
    }

    @MainActor
    private func configureAudioSessionForTesting() {
        ManabiSpokenAudioSession.activationOverrideForTesting = { _ in }
        ManabiSpokenAudioSession.deactivationOverrideForTesting = {}
    }

    func testKanaScriptConversionPreservesNoOpInputAndConvertsMatchingScript() {
        XCTAssertEqual("かな漢字".withKatakanaToHiragana, "かな漢字")
        XCTAssertEqual("カナ漢字".withKatakanaToHiragana, "かな漢字")
        XCTAssertEqual("カナ漢字".withHiraganaToKatakana, "カナ漢字")
        XCTAssertEqual("かな漢字".withHiraganaToKatakana, "カナ漢字")
    }

    func testKanaIterationMarkExpansion() {
        XCTAssertNil("普通の言葉".expandingJapaneseKanaIterationMarks())
        XCTAssertEqual("すゝめ".expandingJapaneseKanaIterationMarks(), "すすめ")
        XCTAssertEqual("いすゞ".expandingJapaneseKanaIterationMarks(), "いすず")
        XCTAssertEqual("クヽ".expandingJapaneseKanaIterationMarks(), "クク")
        XCTAssertEqual("スヾ".expandingJapaneseKanaIterationMarks(), "スズ")
        let decomposedZu = "す\u{3099}"
        XCTAssertEqual((decomposedZu + "ゝ").expandingJapaneseKanaIterationMarks(), decomposedZu + decomposedZu)
        XCTAssertEqual((decomposedZu + "ゞ").expandingJapaneseKanaIterationMarks(), decomposedZu + decomposedZu)
    }

    
    // MARK: - withKanaToRomaji Tests
    
    func testBasicHiragana() {
        let cases: [(String, String)] = [
            ("あいうえお", "aiueo"),
            ("かきくけこ", "kakikukeko"),
            ("さしすせそ", "sasisuseso"),
            ("たちつてと", "tachitsuteto"),
            ("なにぬねの", "naninuneno"),
            ("はひふへほ", "hahifuheho"),
            ("まみむめも", "mamimumemo"),
            ("やゆよ", "yayuyo"),
            ("らりるれろ", "rarirurero"),
            ("わをん", "wawon")
        ]
        for (kana, expected) in cases {
            XCTAssertEqual(kana.withKanaToRomaji, expected, kana)
        }
    }
    
    func testBasicKatakana() {
        let cases: [(String, String)] = [
            ("アイウエオ", "aiueo"),
            ("カキクケコ", "kakikukeko"),
            ("サシスセソ", "sasisuseso"),
            ("タチツテト", "tachitsuteto"),
            ("ナニヌネノ", "naninuneno"),
            ("ハヒフヘホ", "hahifuheho"),
            ("マミムメモ", "mamimumemo"),
            ("ヤユヨ", "yayuyo"),
            ("ラリルレロ", "rarirurero"),
            ("ワヲン", "wawon")
        ]
        for (kana, expected) in cases {
            XCTAssertEqual(kana.withKanaToRomaji, expected, kana)
        }
    }
    
    func testYoonAndDigraphs() {
        let cases: [(String, String)] = [
            ("きゃきゅきょ", "kyak Yukyo".replacingOccurrences(of: " ", with: "").lowercased()), // guard against accidental spaces
            ("しゃしゅしょ", "syasyusyo"),
            ("ちゃちゅちょ", "chachucho"),
            ("じゃじゅじょ", "zyazyuzyo"),
            ("にゃにゅにょ", "nyanyunyo"),
            ("ひゃひゅひょ", "hyahyu hyo".replacingOccurrences(of: " ", with: "")),
            ("みゃみゅみょ", "myamyumyo"),
            ("りゃりゅりょ", "ryaryuryo"),
            ("しぇ", "she"),
            ("ちぇ", "che"),
            ("じぇ", "je"),
            ("てぃ", "thi"),
            ("でゅ", "dhu"),
            ("ふぁふぃふぇふぉ", "fafif efo".replacingOccurrences(of: " ", with: "")),
            ("つぁつぃつぇつぉ", "tsatsitse tso".replacingOccurrences(of: " ", with: "")),
            ("ゔぁゔぃゔゔぇゔぉ", "vavivuv evo".replacingOccurrences(of: " ", with: "")),
            ("うぃうぇうぉ", "whiwhewho"),
            ("くぁくぃくぅくぇくぉ", "kwakwikwukwekwo"),
            ("ぐぁぐぃぐぅぐぇぐぉ", "gwagwigwugwegwo")
        ]
        for (kana, expected) in cases {
            XCTAssertEqual(kana.withKanaToRomaji, expected, kana)
        }
    }
    
    func testSokuon() {
        XCTAssertEqual("きって".withKanaToRomaji, "kitte")
        XCTAssertEqual("キャップ".withKanaToRomaji, "kyappu")
        // Unknown next romaji-leading vowel -> falls back to "xtu"
        XCTAssertEqual("っ".withKanaToRomaji, "xtu")
    }
    
    func testChoonpu() {
        XCTAssertEqual("スーパー".withKanaToRomaji, "suupaa")
        XCTAssertEqual("らーめん".withKanaToRomaji, "raamen")
    }
    
    func testNBeforeVowelOrY() {
        XCTAssertEqual("ほん".withKanaToRomaji, "hon")
        XCTAssertEqual("こんや".withKanaToRomaji, "kon'ya")
        XCTAssertEqual("かんい".withKanaToRomaji, "kan'i")
        XCTAssertEqual("しんよう".withKanaToRomaji, "sin'you")
    }
    
    func testPunctuationAndSpaces() {
        XCTAssertEqual("こんにちは。".withKanaToRomaji, "konnichiha.")
        XCTAssertEqual("はい、そうです！".withKanaToRomaji, "hai,soudesu!")
        XCTAssertEqual("テスト　テスト？".withKanaToRomaji, "tesuto tesuto?")
    }
    
    func testMixedContentPassthrough() {
        XCTAssertEqual("東京タワー is 高い".withKanaToRomaji, "東京tawaa is 高i")
        XCTAssertEqual("A😊カナ".withKanaToRomaji, "A😊kana")
    }

    func testKanjiCount() {
        XCTAssertEqual("物凄い".kanjiCount, 2)
        XCTAssertEqual("食べる".kanjiCount, 1)
        XCTAssertEqual("スピードスケート".kanjiCount, 0)
        XCTAssertEqual("𠀋百円".kanjiCount, 3)
    }

    func testOrderedDistinctKanji() {
        XCTAssertEqual("百円百".orderedDistinctKanji, ["百", "円"])
        XCTAssertEqual("スピードスケート".orderedDistinctKanji, [])
        XCTAssertEqual("𠀋百円𠀋".orderedDistinctKanji, ["𠀋", "百", "円"])
    }

    func testASCIIRepresentationPreservesASCIIAndEncodesUnicodeScalars() {
        let input = "A雨𠀋e\u{301}"
        let encoded = "A\\\\U000096E8\\\\U0002000Be\\\\U00000301"

        XCTAssertEqual(input.asciiRepresentation, encoded)
        XCTAssertEqual(encoded.fromAsciiRepresentation(), input)
        XCTAssertEqual("plain-ASCII_123".asciiRepresentation, "plain-ASCII_123")
    }
    
    func testTrailingSokuonEdgeCase() {
        XCTAssertEqual("あっ".withKanaToRomaji, "axtu")
    }
    
    func testRoundTripWithRomajiToHiragana() {
        // These should round-trip under the same scheme used by the forward mapper.
        let romajiSamples = [
            "sya", "cha", "si", "chi", "tsu", "kya", "hon", "kon'ya", "raamen", "suupaa"
        ]
        for r in romajiSamples {
            let roundTripped = r.withRomajiToHiragana.withKanaToRomaji
            XCTAssertEqual(roundTripped, r, "Round-trip failed for \(r)")
        }
    }

    func testBeginnerHepburnRomajiUsesLearnerSpellings() {
        XCTAssertEqual("しちつふじ".withKanaToBeginnerHepburnRomaji, "shichitsufuji")
        XCTAssertEqual("つ".withKanaToBeginnerHepburnRomaji, "tsu")
        XCTAssertEqual("つく".withKanaToBeginnerHepburnRomaji, "tsuku")
        XCTAssertEqual("ティー".withKanaToBeginnerHepburnRomaji, "tii")
        XCTAssertEqual("しゃしゅしょ".withKanaToBeginnerHepburnRomaji, "shashusho")
        XCTAssertEqual("じゃじゅじょ".withKanaToBeginnerHepburnRomaji, "jajujo")
    }

    func testBeginnerHepburnRomajiLongVowelsAndSokuon() {
        XCTAssertEqual("がっこう".withKanaToBeginnerHepburnRomaji, "gakkou")
        XCTAssertEqual("コーヒー".withKanaToBeginnerHepburnRomaji, "koohii")
        XCTAssertEqual("こっち".withKanaToBeginnerHepburnRomaji, "kocchi")
        XCTAssertEqual("まっちゃ".withKanaToBeginnerHepburnRomaji, "maccha")
        XCTAssertEqual("ひっしゃ".withKanaToBeginnerHepburnRomaji, "hissha")
        XCTAssertEqual("ひっ".withKanaToBeginnerHepburnRomaji, "hit")
    }

    func testBeginnerHepburnRomajiNBeforeVowelOrY() {
        XCTAssertEqual("ほん".withKanaToBeginnerHepburnRomaji, "hon")
        XCTAssertEqual("んあ".withKanaToBeginnerHepburnRomaji, "n'a")
        XCTAssertEqual("んや".withKanaToBeginnerHepburnRomaji, "n'ya")
        XCTAssertEqual("しんよう".withKanaToBeginnerHepburnRomaji, "shin'you")
    }
}
