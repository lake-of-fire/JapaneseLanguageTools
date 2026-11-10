import XCTest
import JapaneseText

final class RubyTextProjectionTests: XCTestCase {
    func testComponentsPreserveExactSourceAndAgreeWithProjectionGrammar() {
        for text in [
            "", "そのまま", "前｜猫《ねこ》と｜犬《いぬ》後",
            "前｜壊れ｜猫《ねこ》後", "｜猫《ね｜こ》", "｜猫《》",
            "<ruby class='mnb-src'>猫<rt>ねこ</rt></ruby>後",
            "<ruby>猫</ruby>と｜犬《いぬ》", "か｜\u{3099}字《がじ》",
            "｜丽《れい》｜丸《まる》", "｜葛《かつ》\u{E0100}",
        ] {
            let components = rubyTextComponents(in: text)
            let projection = projectRubyText(text)
            XCTAssertEqual(Array(components.map(\.source).joined().utf8), Array(text.utf8), text)
            XCTAssertEqual(Array(components.map(\.surface).joined().utf8), Array(projection.surface.utf8), text)
            XCTAssertEqual(Array(components.map { $0.reading ?? $0.surface }.joined().utf8),
                           Array(projection.reading.utf8), text)
            XCTAssertEqual(components.contains { $0.reading != nil }, projection.containsRuby, text)
        }
    }

    func testPipeOnlyComponentsRetainHTMLAndExactScalarBoundaries() {
        let html = "<ruby>東京<rt>とうきょう</rt></ruby>"
        let text = html + "か｜\u{3099}字《がじ》｜葛《かつ》\u{FE00}"
        let components = rubyTextComponents(in: text, includingHTML: false)
        XCTAssertEqual(components.map(\.reading), [nil, "がじ", "かつ", nil])
        XCTAssertEqual(components.map { Array($0.surface.utf8) },
                       [html + "か", "\u{3099}字", "葛", "\u{FE00}"].map { Array($0.utf8) })
        XCTAssertEqual(Array(components.map(\.source).joined().utf8), Array(text.utf8))
        for malformed in ["｜東京", "｜東京《》", "｜東京《とう｜きょう》"] {
            let rejected = rubyTextComponents(in: malformed, includingHTML: false)
            XCTAssertEqual(rejected.map(\.source), [malformed])
            XCTAssertEqual(rejected.map(\.surface), [malformed])
            XCTAssertEqual(rejected.map(\.reading), [nil])
        }
    }

    func testProjectsAozoraRubyToCanonicalSurfaceAndReading() {
        let projection = projectRubyText("前｜猫《ねこ》後")

        XCTAssertEqual(projection.surface, "前猫後")
        XCTAssertEqual(projection.reading, "前ねこ後")
        XCTAssertTrue(projection.containsRuby)
        XCTAssertEqual("前｜猫《ねこ》後".removingRubyText, projection.surface)
        XCTAssertEqual("前｜猫《ねこ》後".replacingRubyText, projection.reading)
    }

    func testProjectsGeneratedHTMLRubyToCanonicalSurfaceAndReading() {
        let projection = projectRubyText("前<ruby>猫<rt>ねこ</rt></ruby>後")

        XCTAssertEqual(projection.surface, "前猫後")
        XCTAssertEqual(projection.reading, "前ねこ後")
        XCTAssertTrue(projection.containsRuby)
    }

    func testProjectsGeneratedRubyAttributesAndSurfaceWrapper() {
        let markup = """
        <ruby class='mnb-gen' data-comparison='1 > 0'><m-t>猫</m-t><rt aria-label="reading">ねこ</rt></ruby>
        """
        let projection = projectRubyText(markup)

        XCTAssertEqual(projection.surface, "猫")
        XCTAssertEqual(projection.reading, "ねこ")
        XCTAssertTrue(projection.containsRuby)
    }

    func testProjectsStandardRubyWithNestedTagsAndReadingParentheses() {
        let projection = projectRubyText(
            "前<ruby><rb><span>猫</span></rb><rp>(</rp><rt><em>ねこ</em></rt><rp>)</rp></ruby>後"
        )

        XCTAssertEqual(projection.surface, "前猫後")
        XCTAssertEqual(projection.reading, "前ねこ後")
        XCTAssertTrue(projection.containsRuby)
    }

    func testPreservesUnrelatedMarkupAndTextAroundRuby() {
        let projection = projectRubyText(
            "<b>前</b>｜猫《ねこ》と<ruby>犬<rt>いぬ</rt></ruby><i>後</i>"
        )

        XCTAssertEqual(projection.surface, "<b>前</b>猫と犬<i>後</i>")
        XCTAssertEqual(projection.reading, "<b>前</b>ねこといぬ<i>後</i>")
        XCTAssertTrue(projection.containsRuby)
    }

    func testMalformedRubyIsPreservedInsteadOfPartiallyProjected() {
        let inputs = [
            "前｜《ねこ》後",
            "前｜猫《》後",
            "前<ruby>猫</ruby>後",
            "前<ruby>猫<rt></rt></ruby>後",
        ]

        for input in inputs {
            let projection = projectRubyText(input)
            XCTAssertEqual(projection.surface, input)
            XCTAssertEqual(projection.reading, input)
            XCTAssertFalse(projection.containsRuby)
        }
    }

    func testMalformedAozoraPrefixDoesNotConsumeFollowingValidAnnotation() {
        let projection = projectRubyText("｜壊れた注釈 前｜猫《ねこ》後")

        XCTAssertEqual(projection.surface, "｜壊れた注釈 前猫後")
        XCTAssertEqual(projection.reading, "｜壊れた注釈 前ねこ後")
        XCTAssertTrue(projection.containsRuby)
    }
}
