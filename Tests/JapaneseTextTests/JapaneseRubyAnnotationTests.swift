import XCTest
import JapaneseText

final class JapaneseRubyAnnotationTests: XCTestCase {
    func testRubyPartitioningKeepsAuthoredKanaScalarBytes() {
        for anchor in ["か\u{3099}", "カ\u{3099}", "ｶﾞ", "ﾊﾟ"] {
            let surface = "甲" + anchor + "乙"
            let reading = "あ" + anchor.withKatakanaToHiragana + "い"
            let markup = makeJapaneseRubyMarkup(surface: surface, reading: reading)
            XCTAssertEqual(markup, "｜甲《あ》" + anchor + "｜乙《い》", anchor)
            XCTAssertEqual(Array(projectRubyText(markup).surface.utf8), Array(surface.utf8), anchor)
            XCTAssertEqual(projectRubyText(markup).reading.withKatakanaToHiragana, reading, anchor)
        }
    }

    func testRubyPartitioningMatchesExhaustiveSmallReadingOracle() {
        // Enumerate all positive kanji reading lengths independently of the
        // production bidirectional anchor search, including ambiguous paths.
        func expected(_ runs: [String], _ reading: [Character]) -> String {
            var results: [String] = []
            func visit(_ index: Int, _ offset: Int, _ markup: String) {
                guard results.count < 2 else { return }
                guard index < runs.count else {
                    if offset == reading.count { results.append(markup) }
                    return
                }
                let run = runs[index]
                if run.isKana {
                    let anchor = Array(run.withKatakanaToHiragana)
                    let end = offset + anchor.count
                    if end <= reading.count, reading[offset..<end].elementsEqual(anchor) {
                        visit(index + 1, end, markup + run)
                    }
                } else if offset < reading.count {
                    for end in (offset + 1)...reading.count {
                        visit(index + 1, end, markup + "｜\(run)《\(String(reading[offset..<end]))》")
                    }
                }
            }
            visit(0, 0, "")
            return results.count == 1 ? results[0] : "｜\(runs.joined())《\(String(reading))》"
        }
        var readings = [""]
        for _ in 1...6 {
            readings = readings.flatMap { prefix in ["あ", "に", "な"].map { prefix + $0 } }
            for runs in [["甲", "に", "乙"], ["甲", "に", "乙", "な", "丙"], ["甲", "にな", "乙"]] {
                for reading in readings {
                    XCTAssertEqual(makeJapaneseRubyMarkup(surface: runs.joined(), reading: reading), expected(runs, Array(reading)), runs.joined() + ":" + reading)
                }
            }
        }
    }

    func testRubyPartitioningHandlesLongUniqueAmbiguousAndRepeatedAnchors() {
        let surface = String(repeating: "甲に", count: 2_048) + "乙"
        let reading = String(repeating: "あに", count: 2_048) + "い"
        XCTAssertEqual(makeJapaneseRubyMarkup(surface: surface, reading: reading), String(repeating: "｜甲《あ》に", count: 2_048) + "｜乙《い》")
        let ambiguous = "あに" + reading
        XCTAssertEqual(makeJapaneseRubyMarkup(surface: surface, reading: ambiguous), "｜\(surface)《\(ambiguous)》")

        let anchor = String(repeating: "に", count: 256) + "な"
        let prefix = "あ" + String(repeating: "に", count: 8_192)
        XCTAssertEqual(
            makeJapaneseRubyMarkup(surface: "甲" + anchor + "乙", reading: prefix + "ない"),
            "｜甲《" + "あ" + String(repeating: "に", count: 8_192 - 256) + "》" + anchor + "｜乙《い》"
        )
    }

    func testJapaneseRubyMarkupLeavesInternalKanaUnannotated() {
        for (surface, reading, expected) in [
            ("役に立つ", "やくにたつ", "｜役《やく》に｜立《た》つ"),
            ("取り戻す", "とりもどす", "｜取《と》り｜戻《もど》す"),
            ("お祝い申し上げる", "おいわいもうしあげる", "お｜祝《いわ》い｜申《もう》し｜上《あ》げる"),
            ("役ニ立つ", "ヤクニタツ", "｜役《やく》ニ｜立《た》つ"),
            ("オ役ニ立ツ", "おやくにたつ", "オ｜役《やく》ニ｜立《た》ツ"),
            ("甲に乙に丙", "あにいにう", "｜甲《あ》に｜乙《い》に｜丙《う》"),
            ("かな", "かな", "かな"),
            ("学校", "がっこう", "｜学校《がっこう》"),
            // Both occurrences of に could anchor the internal kana.
            ("甲に乙", "あにいにう", "｜甲に乙《あにいにう》"),
            ("甲に乙", "あいう", "｜甲に乙《あいう》"),
        ] {
            let markup = makeJapaneseRubyMarkup(surface: surface, reading: reading)
            XCTAssertEqual(markup, expected, surface)
            XCTAssertEqual(markup.removingRubyText, surface)
            XCTAssertEqual(markup.replacingRubyText.withKatakanaToHiragana, reading.withKatakanaToHiragana)
        }
    }

}
