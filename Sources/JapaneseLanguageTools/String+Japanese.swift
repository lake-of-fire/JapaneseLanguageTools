import Foundation

private extension Unicode.Scalar {
    var hexa: String { .init(value, radix: 16, uppercase: true) }
}

private extension Character {
    var hexaValues: [String] {
        unicodeScalars
            .map(\.hexa)
            .map { #"\\U"# + repeatElement("0", count: 8-$0.count) + $0 }
    }
}

public extension StringProtocol where Self: RangeReplaceableCollection {
    var asciiRepresentation: String { map { $0.isASCII ? .init($0) : $0.hexaValues.joined() }.joined() }
}

public extension String {
    var isKana: Bool {
        get {
            if isEmpty {
                return false
            }
            // https://stackoverflow.com/a/38723951/89373
            let kanaRanges = [0x3041...0x3096, 0x309d...0x309f, 0x30a1...0x30fa, 0x30fc...0x30ff, 0xff66...0xff9d]
            for scalar in unicodeScalars {
                var inRange = false
                for range in kanaRanges {
                    if range ~= Int(scalar.value) {
                        inRange = true
                    }
                }
                if !inRange {
                    return false
                }
            }
            return true
        }
    }
    
    var hasKana: Bool {
        get {
            // https://stackoverflow.com/a/38723951/89373
            let kanaRanges = [0x3041...0x3096, 0x309d...0x309f, 0x30a1...0x30fa, 0x30fc...0x30ff, 0xff66...0xff9d]
            for scalar in unicodeScalars {
                for range in kanaRanges {
                    if range ~= Int(scalar.value) {
                        return true
                    }
                }
            }
            return false
        }
    }

    var hasKanji: Bool {
        get {
            // CJK Unified Ideographs                   4E00-9FFF   Common
            //                                          19968-40959
            // CJK Unified Ideographs Extension A       3400-4DFF   Rare
            //                                          13312-19967
            // CJK Unified Ideographs Extension B       20000-2A6DF Rare, historic
            //                                          131072-173791
            // CJK Compatibility Ideographs             F900-FAFF   Duplicates, unifiable variants, corporate characters
            //                                          63744-64255
            // CJK Compatibility Ideographs Supplement  2F800-2FA1F Unifiable variants
            //                                          194560-195103
            for scalar in unicodeScalars {
                for (from, to) in [(19968, 40959), (13312, 19967), (131072, 173791), (63744, 64255), (194560, 195103)] {
                    if scalar.value >= UInt32(from) && scalar.value <= UInt32(to) {
                        return true
                    }
                }
            }
            return false
        }
    }
    
    var distinctKanji: Set<String> {
        return Set(map { String($0) }.filter { $0.hasKanji })
    }
    
    var withHiraganaToKatakana: String {
        get {
            return map { String($0) }.map {
                switch $0 {
                case "あ": return "ア"
                case "か": return "カ"
                case "が": return "ガ"
                case "さ": return "サ"
                case "ざ": return "ザ"
                case "た": return "タ"
                case "だ": return "ダ"
                case "な": return "ナ"
                case "は": return "ハ"
                case "ば": return "バ"
                case "ぱ": return "パ"
                case "ま": return "マ"
                case "や": return "ヤ"
                case "ら": return "ラ"
                case "わ": return "ワ"
                case "い": return "イ"
                case "き": return "キ"
                case "ぎ": return "ギ"
                case "し": return "シ"
                case "じ": return "ジ"
                case "ち": return "チ"
                case "ぢ": return "ヂ"
                case "に": return "ニ"
                case "ひ": return "ヒ"
                case "び": return "ビ"
                case "ぴ": return "ピ"
                case "み": return "ミ"
                case "り": return "リ"
                case "ゐ": return "ヰ"
                case "う": return "ウ"
                case "ゔ": return "ヴ"
                case "く": return "ク"
                case "ぐ": return "グ"
                case "す": return "ス"
                case "ず": return "ズ"
                case "つ": return "ツ"
                case "づ": return "ヅ"
                case "ぬ": return "ヌ"
                case "ふ": return "フ"
                case "ぶ": return "ブ"
                case "ぷ": return "プ"
                case "む": return "ム"
                case "ゆ": return "ユ"
                case "る": return "ル"
                case "え": return "エ"
                case "け": return "ケ"
                case "げ": return "ゲ"
                case "せ": return "セ"
                case "ぜ": return "ゼ"
                case "て": return "テ"
                case "で": return "デ"
                case "ね": return "ネ"
                case "へ": return "ヘ"
                case "べ": return "ベ"
                case "ぺ": return "ペ"
                case "め": return "メ"
                case "れ": return "レ"
                case "ゑ": return "ヱ"
                case "お": return "オ"
                case "こ": return "コ"
                case "ご": return "ゴ"
                case "そ": return "ソ"
                case "ぞ": return "ゾ"
                case "と": return "ト"
                case "ど": return "ド"
                case "の": return "ノ"
                case "ほ": return "ホ"
                case "ぼ": return "ボ"
                case "ぽ": return "ポ"
                case "も": return "モ"
                case "よ": return "ヨ"
                case "ろ": return "ロ"
                case "を": return "ヲ"
                case "ん": return "ン"
                case "ぁ": return "ァ"
                case "ぃ": return "ィ"
                case "ぅ": return "ゥ"
                case "ぇ": return "ェ"
                case "ぉ": return "ォ"
                case "っ": return "ッ"
                case "ゃ": return "ャ"
                case "ゅ": return "ュ"
                case "ょ": return "ョ"
                case "ゎ": return "ヮ"
                case "ゕ": return "ヵ"
                case "ゖ": return "ヶ"
                default:
                    return String($0)
                }
            }.joined(separator: "")
        }
    }

    var withKatakanaToHiragana: String {
        get {
            return map { String($0) }.map {
                switch $0 {
                case "ア": return "あ"
                case "カ": return "か"
                case "ガ": return "が"
                case "サ": return "さ"
                case "ザ": return "ざ"
                case "タ": return "た"
                case "ダ": return "だ"
                case "ナ": return "な"
                case "ハ": return "は"
                case "バ": return "ば"
                case "パ": return "ぱ"
                case "マ": return "ま"
                case "ヤ": return "や"
                case "ラ": return "ら"
                case "ワ": return "わ"
                case "イ": return "い"
                case "キ": return "き"
                case "ギ": return "ぎ"
                case "シ": return "し"
                case "ジ": return "じ"
                case "チ": return "ち"
                case "ヂ": return "ぢ"
                case "ニ": return "に"
                case "ヒ": return "ひ"
                case "ビ": return "び"
                case "ピ": return "ぴ"
                case "ミ": return "み"
                case "リ": return "り"
                case "ヰ": return "ゐ"
                case "ウ": return "う"
                case "ヴ": return "ゔ"
                case "ク": return "く"
                case "グ": return "ぐ"
                case "ス": return "す"
                case "ズ": return "ず"
                case "ツ": return "つ"
                case "ヅ": return "づ"
                case "ヌ": return "ぬ"
                case "フ": return "ふ"
                case "ブ": return "ぶ"
                case "プ": return "ぷ"
                case "ム": return "む"
                case "ユ": return "ゆ"
                case "ル": return "る"
                case "エ": return "え"
                case "ケ": return "け"
                case "ゲ": return "げ"
                case "セ": return "せ"
                case "ゼ": return "ぜ"
                case "テ": return "て"
                case "デ": return "で"
                case "ネ": return "ね"
                case "ヘ": return "へ"
                case "ベ": return "べ"
                case "ペ": return "ぺ"
                case "メ": return "め"
                case "レ": return "れ"
                case "ヱ": return "ゑ"
                case "オ": return "お"
                case "コ": return "こ"
                case "ゴ": return "ご"
                case "ソ": return "そ"
                case "ゾ": return "ぞ"
                case "ト": return "と"
                case "ド": return "ど"
                case "ノ": return "の"
                case "ホ": return "ほ"
                case "ボ": return "ぼ"
                case "ポ": return "ぽ"
                case "モ": return "も"
                case "ヨ": return "よ"
                case "ロ": return "ろ"
                case "ヲ": return "を"
                case "ン": return "ん"
                case "ァ": return "ぁ"
                case "ィ": return "ぃ"
                case "ゥ": return "ぅ"
                case "ェ": return "ぇ"
                case "ォ": return "ぉ"
                case "ッ": return "っ"
                case "ャ": return "ゃ"
                case "ュ": return "ゅ"
                case "ョ": return "ょ"
                case "ヮ": return "ゎ"
                case "ヵ": return "ゕ"
                case "ヶ": return "ゖ"
                default:
                    return String($0)
                }
            }.joined(separator: "")
        }
    }

}
