import XCTest
import JapaneseText

final class JapaneseTextTests: XCTestCase {
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

    func testContainsCJKCharactersRecognizesCompatibilityIdeographsAcrossOptions() {
        let cases = [
            ("﨑", true, false, false), ("丽", true, false, false), ("丸", true, false, false),
            ("A﨑B", true, false, false), ("😀丽", true, false, false),
            ("猫", true, false, false), ("𠀀", true, false, false),
            ("あ", false, true, false), ("ア", false, true, false), ("ｱ", false, true, false),
            ("7", false, false, true), ("７", false, false, true),
            ("", false, false, false), ("A", false, false, false), ("😀", false, false, false),
        ]
        for (text, hasCJK, hasKana, hasNumber) in cases {
            for includingKana in [false, true] {
                for includingNumbers in [false, true] {
                    XCTAssertEqual(
                        containsCJKCharacters(text: text, includingKana: includingKana,
                                              includingNumbers: includingNumbers),
                        hasCJK || (includingKana && hasKana) || (includingNumbers && hasNumber),
                        "\(text), kana=\(includingKana), numbers=\(includingNumbers)"
                    )
                }
            }
        }
    }

    func testKanjiClassificationAndExtractionAgreeAtUnicodeBlockBoundaries() {
        // Unicode 17 CJK ideograph blocks: https://www.unicode.org/Public/17.0.0/ucd/Blocks.txt
        let blocks: [ClosedRange<UInt32>] = [
            0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
            0x20000...0x2A6DF, 0x2A700...0x2B73F, 0x2B740...0x2B81F,
            0x2B820...0x2CEAF, 0x2CEB0...0x2EBEF, 0x2EBF0...0x2EE5F,
            0x2F800...0x2FA1F, 0x30000...0x3134F, 0x31350...0x323AF,
            0x323B0...0x3347F,
        ]
        func check<S: StringProtocol>(_ text: S, expected: Bool) {
            let diagnostic = Array(text.unicodeScalars).map { String($0.value, radix: 16) }.joined(separator: ",")
            XCTAssertEqual(text.isKanji, expected, diagnostic)
            XCTAssertEqual(text.hasKanji, expected, diagnostic)
            XCTAssertEqual(text.kanjiCount, expected ? 1 : 0, diagnostic)
            let bytes = expected ? [Array(text.utf8)] : []
            XCTAssertEqual(text.distinctKanji.map { Array($0.utf8) }, bytes, diagnostic)
            XCTAssertEqual(text.orderedDistinctKanji.map { Array($0.utf8) }, bytes, diagnostic)
        }
        let candidates = Set(blocks.flatMap {
            [$0.lowerBound - 1, $0.lowerBound, $0.upperBound, $0.upperBound + 1]
        } + [0x4DFF, 0x2A6FF, 0x2FA3F])
        for rawValue in candidates.sorted() {
            let scalar = UnicodeScalar(rawValue)!
            let text = String(scalar)
            let expected = blocks.contains { $0.contains(rawValue) }
            XCTAssertEqual(isJapaneseKanjiScalar(rawValue), expected, text)
            XCTAssertEqual(isJapaneseKanjiScalar(scalar), expected, text)
            check(text, expected: expected)
            check(("A" + text + "Z").dropFirst().dropLast(), expected: expected)
            for includingKana in [false, true] {
                for includingNumbers in [false, true] {
                    XCTAssertEqual(containsCJKCharacters(text: text, includingKana: includingKana,
                                                       includingNumbers: includingNumbers), expected, text)
                }
            }
            let mixed = "A" + text + "あ" + text + "😀"
            XCTAssertFalse(mixed.isKanji, text)
            XCTAssertEqual(mixed.hasKanji, expected, text)
            XCTAssertEqual(mixed.kanjiCount, expected ? 2 : 0, text)
            let bytes = expected ? [Array(text.utf8)] : []
            XCTAssertEqual(mixed.distinctKanji.map { Array($0.utf8) }, bytes, text)
            XCTAssertEqual(mixed.orderedDistinctKanji.map { Array($0.utf8) }, bytes, text)
            XCTAssertEqual(containsCJKCharacters(text: mixed, includingKana: false,
                                               includingNumbers: false), expected, text)
        }
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
        XCTAssertEqual((decomposedZu + "ゝ").expandingJapaneseKanaIterationMarks(), decomposedZu + "す")
        XCTAssertEqual((decomposedZu + "ゞ").expandingJapaneseKanaIterationMarks(), decomposedZu + "ず")
    }

    func testIterationMarksSelectVoicingIndependentlyOfSourceSoundMarks() {
        // Unicode 17, section 18.4.1: the iteration mark selects unvoiced or voiced.
        // Section 18.4.2 gives the katakana marks the same function.
        let cases = [
            ("がゝ", "がか"), ("がゞ", "がが"),
            ("ぱゝ", "ぱは"), ("ぱゞ", "ぱば"),
            ("ガヽ", "ガカ"), ("ガヾ", "ガガ"),
            ("パヽ", "パハ"), ("パヾ", "パバ"),
            ("か\u{3099}ゝ", "か\u{3099}か"), ("か\u{3099}ゞ", "か\u{3099}が"),
            ("は\u{309A}ゝ", "は\u{309A}は"), ("は\u{309A}ゞ", "は\u{309A}ば"),
            ("カ\u{3099}ヽ", "カ\u{3099}カ"), ("カ\u{3099}ヾ", "カ\u{3099}ガ"),
            ("ハ\u{309A}ヽ", "ハ\u{309A}ハ"), ("ハ\u{309A}ヾ", "ハ\u{309A}バ")
        ]
        for (source, expected) in cases {
            // Byte comparison also proves that the original source syllable stays intact.
            XCTAssertEqual(source.expandingJapaneseKanaIterationMarks().map { Array($0.utf8) },
                           Array(expected.utf8), source)
            let substring = ("A" + source + "Z").dropFirst().dropLast()
            XCTAssertEqual(substring.expandingJapaneseKanaIterationMarks().map { Array($0.utf8) },
                           Array(expected.utf8), source)
        }
    }

    func testIterationExpansionPreservesUnsupportedAndLeadingMarkFallback() {
        for source in ["ゝかな", "ゞかな", "ヽカナ", "ヾカナ", "Aゝ", "猫ヾ", "か ゝ", "すゝ猫ヾ"] {
            XCTAssertNil(source.expandingJapaneseKanaIterationMarks(), source)
        }
        XCTAssertNil("がぱガパ".expandingJapaneseKanaIterationMarks())
        XCTAssertEqual("かゝゞ".expandingJapaneseKanaIterationMarks(), "かかが")
    }

    func testDecomposedIterationMarkIsOneVoicedTokenBeforeAnotherMark() {
        let cases = [
            ("かゝ\u{3099}", "かが"), ("パヽ\u{3099}", "パバ"),
            ("かゝ\u{3099}ゝ", "かがか"), ("カヽ\u{3099}ヽ", "カガカ"),
            ("ぱゝ\u{3099}ゝ", "ぱばは"), ("パヽ\u{3099}ヽ", "パバハ"),
            ("か\u{3099}ゝ\u{3099}ゝ", "か\u{3099}がか"),
            ("は\u{309A}ゝ\u{3099}ゝ", "は\u{309A}ばは"),
            ("かゞ\u{3099}ゝ", "かが\u{3099}か")
        ]
        for (source, expected) in cases {
            XCTAssertEqual(source.expandingJapaneseKanaIterationMarks().map { Array($0.utf8) },
                           Array(expected.utf8), source)
            let substring = ("A" + source + "Z").dropFirst().dropLast()
            XCTAssertEqual(substring.expandingJapaneseKanaIterationMarks().map { Array($0.utf8) },
                           Array(expected.utf8), source)
        }
        XCTAssertNil("ゝ\u{3099}ゝ".expandingJapaneseKanaIterationMarks())
        XCTAssertNil("Aゝ\u{3099}ゝ".expandingJapaneseKanaIterationMarks())
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
