import XCTest
@testable import JapaneseLanguageTools

final class JapaneseLanguageToolsTests: XCTestCase {
    
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
}
