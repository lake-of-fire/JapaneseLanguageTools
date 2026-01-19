// Forked from: https://raw.githubusercontent.com/Kyome22/Kaede/master/Kaede/RomajiToKana.swift
//
//  RomajiToKana.swift
//  Kaede
//
//  Created by Takuto Nakamura on 2020/07/31.
//  Copyright © 2020 Takuto Nakamura. All rights reserved.
//
import Foundation

private enum UnicodeScalarConstants {
    static let katakanaStart: UInt32 = 0x30A1
    static let katakanaEnd: UInt32 = 0x30F6
    static let kanaShift: UInt32 = 0x60
    static let utf8TwoByteMaxScalar: UInt32 = 0x7FF
    static let utf8ThreeByteMaxScalar: UInt32 = 0xFFFF
}

private enum UTF8Constants {
    static let asciiMax: UInt8 = 0x7F
    static let twoByteLeadMax: UInt8 = 0xDF
    static let threeByteLeadMax: UInt8 = 0xEF
    static let fourByteLeadMax: UInt8 = 0xF7

    static let continuationMask: UInt8 = 0xC0
    static let continuationExpected: UInt8 = 0x80

    static let twoByteLeadMask: UInt8 = 0x1F
    static let threeByteLeadMask: UInt8 = 0x0F
    static let fourByteLeadMask: UInt8 = 0x07
    static let sixBitMask: UInt8 = 0x3F

    static let twoByteLeadBase: UInt8 = 0xC0
    static let threeByteLeadBase: UInt8 = 0xE0
    static let fourByteLeadBase: UInt8 = 0xF0
}

@inline(__always)
private func withUTF8Buffer<S: StringProtocol, R>(_ string: S, _ body: (UnsafeBufferPointer<UInt8>) -> R) -> R {
    if let result = string.utf8.withContiguousStorageIfAvailable({ buffer in
        body(buffer)
    }) {
        return result
    }
    var bytes = Array(string.utf8)
    return bytes.withUnsafeBufferPointer { buffer in
        body(buffer)
    }
}

@inline(__always)
private func isContinuationByte(_ byte: UInt8) -> Bool {
    (byte & UTF8Constants.continuationMask) == UTF8Constants.continuationExpected
}

@inline(__always)
private func decodeUTF8Scalar(
    in buffer: UnsafeBufferPointer<UInt8>,
    at index: Int
) -> (scalar: UInt32, length: Int)? {
    let count = buffer.count
    let byte0 = buffer[index]

    if byte0 <= UTF8Constants.asciiMax {
        return (UInt32(byte0), 1)
    }

    if byte0 <= UTF8Constants.twoByteLeadMax {
        let nextIndex = index + 1
        if nextIndex >= count { return nil }
        let byte1 = buffer[nextIndex]
        if !isContinuationByte(byte1) { return nil }
        let scalar = (UInt32(byte0 & UTF8Constants.twoByteLeadMask) << 6)
            | UInt32(byte1 & UTF8Constants.sixBitMask)
        return (scalar, 2)
    }

    if byte0 <= UTF8Constants.threeByteLeadMax {
        let nextIndex = index + 2
        if nextIndex >= count { return nil }
        let byte1 = buffer[index + 1]
        let byte2 = buffer[index + 2]
        if !isContinuationByte(byte1) || !isContinuationByte(byte2) { return nil }
        let scalar = (UInt32(byte0 & UTF8Constants.threeByteLeadMask) << 12)
            | (UInt32(byte1 & UTF8Constants.sixBitMask) << 6)
            | UInt32(byte2 & UTF8Constants.sixBitMask)
        return (scalar, 3)
    }

    if byte0 <= UTF8Constants.fourByteLeadMax {
        let nextIndex = index + 3
        if nextIndex >= count { return nil }
        let byte1 = buffer[index + 1]
        let byte2 = buffer[index + 2]
        let byte3 = buffer[index + 3]
        if !isContinuationByte(byte1) || !isContinuationByte(byte2) || !isContinuationByte(byte3) { return nil }
        let scalar = (UInt32(byte0 & UTF8Constants.fourByteLeadMask) << 18)
            | (UInt32(byte1 & UTF8Constants.sixBitMask) << 12)
            | (UInt32(byte2 & UTF8Constants.sixBitMask) << 6)
            | UInt32(byte3 & UTF8Constants.sixBitMask)
        return (scalar, 4)
    }

    return nil
}

@inline(__always)
private func encodeUTF8Scalar(_ scalar: UInt32, into output: inout [UInt8]) {
    if scalar <= UInt32(UTF8Constants.asciiMax) {
        output.append(UInt8(scalar))
        return
    }

    if scalar <= UnicodeScalarConstants.utf8TwoByteMaxScalar {
        output.append(UTF8Constants.twoByteLeadBase | UInt8((scalar >> 6) & UInt32(UTF8Constants.twoByteLeadMask)))
        output.append(UTF8Constants.continuationExpected | UInt8(scalar & UInt32(UTF8Constants.sixBitMask)))
        return
    }

    if scalar <= UnicodeScalarConstants.utf8ThreeByteMaxScalar {
        output.append(UTF8Constants.threeByteLeadBase | UInt8((scalar >> 12) & UInt32(UTF8Constants.threeByteLeadMask)))
        output.append(UTF8Constants.continuationExpected | UInt8((scalar >> 6) & UInt32(UTF8Constants.sixBitMask)))
        output.append(UTF8Constants.continuationExpected | UInt8(scalar & UInt32(UTF8Constants.sixBitMask)))
        return
    }

    output.append(UTF8Constants.fourByteLeadBase | UInt8((scalar >> 18) & UInt32(UTF8Constants.fourByteLeadMask)))
    output.append(UTF8Constants.continuationExpected | UInt8((scalar >> 12) & UInt32(UTF8Constants.sixBitMask)))
    output.append(UTF8Constants.continuationExpected | UInt8((scalar >> 6) & UInt32(UTF8Constants.sixBitMask)))
    output.append(UTF8Constants.continuationExpected | UInt8(scalar & UInt32(UTF8Constants.sixBitMask)))
}

public extension String {
    var withRomajiToHiragana: String {
        var str = self
        var n: Int = 0
        while str.count >= 2 && n < str.count - 1 {
            let strL = String(str[str.startIndex ..< str.index(str.startIndex, offsetBy: n)])
            let strC = String(str[str.index(str.startIndex, offsetBy: n) ..< str.index(str.startIndex, offsetBy: n + 2)])
            let strR = String(str[str.index(str.startIndex, offsetBy: n + 2) ..< str.endIndex])
            str = strL + Self.nCheck(strC) + strR
            n += 1
        }
        n = 0
        while str.count >= 2 && n < str.count - 1 {
            let strL = String(str[str.startIndex ..< str.index(str.startIndex, offsetBy: n)])
            let strC = String(str[str.index(str.startIndex, offsetBy: n) ..< str.index(str.startIndex, offsetBy: n + 2)])
            let strR = String(str[str.index(str.startIndex, offsetBy: n + 2) ..< str.endIndex])
            str = strL + Self.xtuCheck(strC) + strR
            n += 1
        }
        for i in (1 ... 4).reversed() {
            n = 0
            while str.count >= i && n < str.count - (i - 1) {
                let strL = String(str[str.startIndex ..< str.index(str.startIndex, offsetBy: n)])
                let strC = String(str[str.index(str.startIndex, offsetBy: n) ..< str.index(str.startIndex, offsetBy: n + i)])
                let strR = String(str[str.index(str.startIndex, offsetBy: n + i) ..< str.endIndex])
                str = strL + Self.convert(strC) + strR
                n += 1
            }
        }
        return str
    }
    
    private static func nCheck(_ str: String) -> String {
        switch str.lowercased() {
        case "na": return str
        case "ni": return str
        case "nu": return str
        case "ne": return str
        case "no": return str
        case "ny": return str
        case "n'", "nn": return "ん"
        default: return str
        }
    }
    
    private static func isRoman(_ str: String) -> Bool {
        return NSPredicate(format: "SELF MATCHES %@", "[a-zA-Z]+").evaluate(with: str)
    }
    
    private static func xtuCheck(_ str: String) -> String {
        let c0 = str.first!.lowercased()
        let c1 = String(str.last!)
        if isRoman(c0) && c0 == c1.lowercased() {
            if c0 == "a" || c0 == "i" || c0 == "u" || c0 == "e" || c0 == "o" {
                return str
            } else {
                return "っ" + c1
            }
        }
        return str
    }
    
    private static func convert(_ str: String) -> String {
        switch str.count {
        case 1:
            return one(str)
        case 2:
            return two(str)
        case 3:
            switch str.dropFirst().first!.lowercased() {
            case "y": return threeY(str)
            case "h": return threeH(str)
            case "w": return threeW(str)
            default:
                switch str.lowercased() {
                case "tsa": return "つぁ"
                case "tsi": return "つぃ"
                case "tsu": return "つ"
                case "tse": return "つぇ"
                case "tso": return "つぉ"
                case "xtu", "ltu": return "っ"
                default: break
                }
                return str
            }
        case 4:
            return (str.lowercased() == "xtsu" || str.lowercased() == "ltsu") ? "っ" : str
        default:
            return str
        }
    }
    
    private static func one(_ str: String) -> String {
        switch str.lowercased() {
        case "a": return "あ"
        case "i": return "い"
        case "u": return "う"
        case "e": return "え"
        case "o": return "お"
        case "n": return "ん"
        case "1": return "１"
        case "2": return "２"
        case "3": return "３"
        case "4": return "４"
        case "5": return "５"
        case "6": return "６"
        case "7": return "７"
        case "8": return "８"
        case "9": return "９"
        case "0": return "０"
        case ".": return "。"
        case ",": return "、"
        case "!": return "！"
        case "?": return "？"
        case ":": return "："
        case ";": return "；"
        case "-": return "ー"
        case "+": return "＋"
        case "*": return "＊"
        case "/": return "／"
        case "\\": return "＼"
        case "|": return "｜"
        case "^": return "＾"
        case "=": return "＝"
        case "_": return "＿"
        case "@": return "＠"
        case "\'": return "’"
        case "\"": return "”"
        case "`": return "｀"
        case "~": return "〜"
        case "#": return "＃"
        case "$": return "＄"
        case "%": return "％"
        case "&": return "＆"
        case "(": return "（"
        case ")": return "）"
        case "[": return "「"
        case "]": return "」"
        case "{": return "『"
        case "}": return "』"
        case "<": return "＜"
        case ">": return "＞"
        case " ": return "　"
        default: return str
        }
    }
    
    private static func two(_ str: String) -> String {
        switch str.lowercased() {
        case "ba": return "ば"
        case "bi": return "び"
        case "bu": return "ぶ"
        case "be": return "べ"
        case "bo": return "ぼ"
        case "da": return "だ"
        case "di": return "ぢ"
        case "du": return "づ"
        case "de": return "で"
        case "do": return "ど"
        case "fa": return "ふぁ"
        case "fi": return "ふぃ"
        case "fu": return "ふ"
        case "fe": return "ふぇ"
        case "fo": return "ふぉ"
        case "ga": return "が"
        case "gi": return "ぎ"
        case "gu": return "ぐ"
        case "ge": return "げ"
        case "go": return "ご"
        case "ha": return "は"
        case "hi": return "ひ"
        case "hu": return "ふ"
        case "he": return "へ"
        case "ho": return "ほ"
        case "ja": return "じゃ"
        case "ji": return "じ"
        case "ju": return "じゅ"
        case "je": return "じぇ"
        case "jo": return "じょ"
        case "ka": return "か"
        case "ki": return "き"
        case "ku": return "く"
        case "ke": return "け"
        case "ko": return "こ"
        case "ma": return "ま"
        case "mi": return "み"
        case "mu": return "む"
        case "me": return "め"
        case "mo": return "も"
        case "na": return "な"
        case "ni": return "に"
        case "nu": return "ぬ"
        case "ne": return "ね"
        case "no": return "の"
        case "pa": return "ぱ"
        case "pi": return "ぴ"
        case "pu": return "ぷ"
        case "pe": return "ぺ"
        case "po": return "ぽ"
        case "qa": return "くぁ"
        case "qi": return "くい"
        case "qu": return "くぅ"
        case "qe": return "くぇ"
        case "qo": return "くぉ"
        case "ra": return "ら"
        case "ri": return "り"
        case "ru": return "る"
        case "re": return "れ"
        case "ro": return "ろ"
        case "sa": return "さ"
        case "si": return "し"
        case "su": return "す"
        case "se": return "せ"
        case "so": return "そ"
        case "ta": return "た"
        case "ti": return "ち"
        case "tu": return "つ"
        case "te": return "て"
        case "to": return "と"
        case "va": return "ゔぁ"
        case "vi": return "ゔぃ"
        case "vu": return "ゔ"
        case "ve": return "ゔぇ"
        case "vo": return "ゔぉ"
        case "wa": return "わ"
        case "wi": return "うぃ"
        case "wu": return "う"
        case "we": return "うぇ"
        case "wo": return "を"
        case "xa": return "ぁ"
        case "xi": return "ぃ"
        case "xu": return "ぅ"
        case "xe": return "ぇ"
        case "xo": return "ぉ"
        case "ya": return "や"
        case "yu": return "ゆ"
        case "yo": return "よ"
        case "za": return "ざ"
        case "zi": return "じ"
        case "zu": return "ず"
        case "ze": return "ぜ"
        case "zo": return "ぞ"
        default: return str
        }
    }
    
    private static func threeY(_ str: String) -> String {
        func yaiueo(head: String, str: String) -> String {
            switch str.lowercased() {
            case "ya": return head + "ゃ"
            case "yi": return head + "ぃ"
            case "yu": return head + "ゅ"
            case "ye": return head + "ぇ"
            case "yo": return head + "ょ"
            default: return str
            }
        }
        switch str.first!.lowercased() {
        case "b": return yaiueo(head: "び", str: String(str.dropFirst()))
        case "c": return yaiueo(head: "ち", str: String(str.dropFirst()))
        case "d": return yaiueo(head: "ぢ", str: String(str.dropFirst()))
        case "f": return yaiueo(head: "ふ", str: String(str.dropFirst()))
        case "g": return yaiueo(head: "ぎ", str: String(str.dropFirst()))
        case "h": return yaiueo(head: "ひ", str: String(str.dropFirst()))
        case "j": return yaiueo(head: "じ", str: String(str.dropFirst()))
        case "k": return yaiueo(head: "き", str: String(str.dropFirst()))
        case "l": return yaiueo(head: "", str: String(str.dropFirst()))
        case "m": return yaiueo(head: "み", str: String(str.dropFirst()))
        case "n": return yaiueo(head: "に", str: String(str.dropFirst()))
        case "p": return yaiueo(head: "ぴ", str: String(str.dropFirst()))
        case "r": return yaiueo(head: "り", str: String(str.dropFirst()))
        case "s": return yaiueo(head: "し", str: String(str.dropFirst()))
        case "t": return yaiueo(head: "ち", str: String(str.dropFirst()))
        case "v": return yaiueo(head: "ゔ", str: String(str.dropFirst()))
        case "x": return yaiueo(head: "", str: String(str.dropFirst()))
        case "z": return yaiueo(head: "じ", str: String(str.dropFirst()))
        default:
            if str.lowercased() == "wyi" {
                return "ゐ"
            } else if str.lowercased() == "wye" {
                return "ゑ"
            } else {
                return str
            }
        }
    }
    
    private static func threeH(_ str: String) -> String {
        switch str.lowercased() {
        case "cha": return "ちゃ"
        case "chi": return "ち"
        case "chu": return "ちゅ"
        case "che": return "ちぇ"
        case "cho": return "ちょ"
        case "dha": return "でゃ"
        case "dhi": return "でぃ"
        case "dhu": return "でゅ"
        case "dhe": return "でぇ"
        case "dho": return "でょ"
        case "sha": return "しゃ"
        case "shi": return "し"
        case "shu": return "しゅ"
        case "she": return "しぇ"
        case "sho": return "しょ"
        case "tha": return "てゃ"
        case "thi": return "てぃ"
        case "thu": return "てゅ"
        case "the": return "てぇ"
        case "tho": return "てょ"
        case "wha": return "うぁ"
        case "whi": return "うぃ"
        case "whu": return "う"
        case "whe": return "うぇ"
        case "who": return "うぉ"
        default: return str
        }
    }
    
    private static func threeW(_ str: String) -> String {
        switch str.lowercased() {
        case "dwa": return "どぁ"
        case "dwi": return "どぃ"
        case "dwu": return "どぅ"
        case "dwe": return "どぇ"
        case "dwo": return "どぉ"
        case "gwa": return "ぐぁ"
        case "gwi": return "ぐぃ"
        case "gwu": return "ぐぅ"
        case "gwe": return "ぐぇ"
        case "gwo": return "ぐぉ"
        case "kwa": return "くぁ"
        case "kwi": return "くぃ"
        case "kwu": return "くぅ"
        case "kwe": return "くぇ"
        case "kwo": return "くぉ"
        case "lwa": return "ゎ"
        case "swa": return "すぁ"
        case "swi": return "すぃ"
        case "swu": return "すぅ"
        case "swe": return "すぇ"
        case "swo": return "すぉ"
        case "twa": return "とぁ"
        case "twi": return "とぃ"
        case "twu": return "とぅ"
        case "twe": return "とぇ"
        case "two": return "とぉ"
        case "xwa": return "ゎ"
        default: return str
        }
    }
    
    /// Converts Hiragana **and** Katakana to romaji.
    /// - Notes:
    ///   - Mirrors the same scheme accepted by `withRomajiToHiragana` so round‑trips are predictable.
    ///   - Prefers Nihon-shiki style forms used in this file’s forward mapping (e.g. `si/ti/tu`, `sya/tya`).
    ///   - Handles sokuon (っ) by doubling the following consonant, chōonpu (ー) as `-`, and `ん` as `n` or `n'` before vowels/`y`.
    var withKanaToRomaji: String {
        let src = Self.normalizeToHiragana(self)
        var out = ""
        var i = src.startIndex
        var pendingSokuon = false
        
        while i < src.endIndex {
            let ch = src[i]
            
            // Prolonged sound mark: repeat previous vowel (e.g., スーパー -> suupaa). If none, drop the mark.
            if ch == "ー" {
                // Repeat the previous vowel (e.g., スーパー -> suupaa). If none, drop the mark.
                if let v = out.last(where: { "aeiouAEIOU".contains($0) }) {
                    out.append(v)
                }
                i = src.index(after: i)
                continue
            }
            
            // Small tsu (sokuon) -> hold for next syllable
            if ch == "っ" {
                pendingSokuon = true
                i = src.index(after: i)
                continue
            }
            
            // 'n' syllable
            if ch == "ん" {
                // Look ahead to decide between "n" and "n'"
                if let first = Self.peekNextRomajiFirst(hiragana: src, from: src.index(after: i)),
                   "aiueoyAIUEOY".contains(first) {
                    out += "n'"
                } else {
                    out += "n"
                }
                i = src.index(after: i)
                continue
            }
            
            // Punctuation and zenkaku symbols back to ASCII
            if let mapped = Self.kanaPunctToAscii[ch] {
                out += mapped
                i = src.index(after: i)
                continue
            }
            
            // Try two-char kana sequences first (yoon & special digraphs)
            var consumed = false
            if let j = src.index(i, offsetBy: 1, limitedBy: src.endIndex), j < src.endIndex {
                let two = String(src[i...j])
                if var romaji = Self.kanaToRomajiTwo[two] {
                    if pendingSokuon {
                        romaji = Self.applySokuon(to: romaji)
                        pendingSokuon = false
                    }
                    out += romaji
                    i = src.index(after: j)
                    consumed = true
                }
            }
            if consumed { continue }
            
            // Single kana
            let one = String(ch)
            if var romaji = Self.kanaToRomajiOne[one] {
                if pendingSokuon {
                    romaji = Self.applySokuon(to: romaji)
                    pendingSokuon = false
                }
                out += romaji
                i = src.index(after: i)
                continue
            }
            
            // Unknown character (kanji/latin/etc.) – emit as-is
            out.append(ch)
            i = src.index(after: i)
        }
        
        // Trailing sokuon with no following kana (rare) -> "xtu" for symmetry with forward mapping.
        if pendingSokuon { out += "xtu" }
        
        return out
    }
    
    // MARK: - Kana -> Romaji tables (mirror forward mapping choices)
    
    private static let kanaToRomajiTwo: [String: String] = {
        var m: [String: String] = [:]
        
        // Yoon (contracted) syllables
        let base: [(String, String)] = [
            ("きゃ","kya"),("きゅ","kyu"),("きょ","kyo"),
            ("ぎゃ","gya"),("ぎゅ","gyu"),("ぎょ","gyo"),
            ("しゃ","sya"),("しゅ","syu"),("しょ","syo"),
            ("じゃ","zya"),("じゅ","zyu"),("じょ","zyo"),
            ("ちゃ","cha"),("ちゅ","chu"),("ちょ","cho"),
            ("にゃ","nya"),("にゅ","nyu"),("にょ","nyo"),
            ("ひゃ","hya"),("ひゅ","hyu"),("ひょ","hyo"),
            ("びゃ","bya"),("びゅ","byu"),("びょ","byo"),
            ("ぴゃ","pya"),("ぴゅ","pyu"),("ぴょ","pyo"),
            ("みゃ","mya"),("みゅ","myu"),("みょ","myo"),
            ("りゃ","rya"),("りゅ","ryu"),("りょ","ryo")
        ]
        base.forEach { m[$0.0] = $0.1 }
        
        // She/che/je
        m["しぇ"] = "she"
        m["ちぇ"] = "che"
        m["じぇ"] = "je"
        
        // Thi/dhi/thu/dhu + the/dhe/tho/dho
        m["てぃ"] = "thi"; m["でぃ"] = "dhi"
        m["てゅ"] = "thu"; m["でゅ"] = "dhu"
        m["てゃ"] = "tha"; m["でゃ"] = "dha"
        m["てぇ"] = "the"; m["でぇ"] = "dhe"
        m["てょ"] = "tho"; m["でょ"] = "dho"
        
        // Fa/fi/fe/fo
        m["ふぁ"] = "fa"; m["ふぃ"] = "fi"; m["ふぇ"] = "fe"; m["ふぉ"] = "fo"
        
        // Vu family
        m["ゔぁ"] = "va"; m["ゔぃ"] = "vi"; m["ゔ"] = "vu"; m["ゔぇ"] = "ve"; m["ゔぉ"] = "vo"
        
        // Tsa/tsi/tse/tso
        m["つぁ"] = "tsa"; m["つぃ"] = "tsi"; m["つぇ"] = "tse"; m["つぉ"] = "tso"
        
        // Wh‑ series (maps seen in threeH)
        m["うぁ"] = "wha"; m["うぃ"] = "whi"; m["うぇ"] = "whe"; m["うぉ"] = "who"
        
        // W‑ combos from threeW (kwa/gwa/swa/twa/dwa etc.)
        m["くぁ"] = "kwa"; m["くぃ"] = "kwi"; m["くぅ"] = "kwu"; m["くぇ"] = "kwe"; m["くぉ"] = "kwo"
        m["ぐぁ"] = "gwa"; m["ぐぃ"] = "gwi"; m["ぐぅ"] = "gwu"; m["ぐぇ"] = "gwe"; m["ぐぉ"] = "gwo"
        m["すぁ"] = "swa"; m["すぃ"] = "swi"; m["すぅ"] = "swu"; m["すぇ"] = "swe"; m["すぉ"] = "swo"
        m["とぁ"] = "twa"; m["とぃ"] = "twi"; m["とぅ"] = "twu"; m["とぇ"] = "twe"; m["とぉ"] = "two"
        m["どぁ"] = "dwa"; m["どぃ"] = "dwi"; m["どぅ"] = "dwu"; m["どぇ"] = "dwe"; m["どぉ"] = "dwo"
        
        // Small vowels combos often used alone
        m["ゎ"] = "xwa"
        
        return m
    }()
    
    private static let kanaToRomajiOne: [String: String] = [
        // Basic vowels
        "あ":"a","い":"i","う":"u","え":"e","お":"o",
        // K
        "か":"ka","き":"ki","く":"ku","け":"ke","こ":"ko",
        "が":"ga","ぎ":"gi","ぐ":"gu","げ":"ge","ご":"go",
        // S
        "さ":"sa","し":"si","す":"su","せ":"se","そ":"so",
        "ざ":"za","じ":"zi","ず":"zu","ぜ":"ze","ぞ":"zo",
        // T
        "た":"ta","ち":"chi","つ":"tsu","て":"te","と":"to",
        "だ":"da","ぢ":"di","づ":"du","で":"de","ど":"do",
        // N
        "な":"na","に":"ni","ぬ":"nu","ね":"ne","の":"no",
        // H
        "は":"ha","ひ":"hi","ふ":"fu","へ":"he","ほ":"ho",
        "ば":"ba","び":"bi","ぶ":"bu","べ":"be","ぼ":"bo",
        "ぱ":"pa","ぴ":"pi","ぷ":"pu","ぺ":"pe","ぽ":"po",
        // M
        "ま":"ma","み":"mi","む":"mu","め":"me","も":"mo",
        // Y
        "や":"ya","ゆ":"yu","よ":"yo",
        // R
        "ら":"ra","り":"ri","る":"ru","れ":"re","ろ":"ro",
        // W and historical kana
        "わ":"wa","ゐ":"wyi","ゑ":"wye","を":"wo",
        // Vu
        "ゔ":"vu",
        // Small vowels & small y/w
        "ぁ":"xa","ぃ":"xi","ぅ":"xu","ぇ":"xe","ぉ":"xo",
        "ゃ":"xya","ゅ":"xyu","ょ":"xyo","ゎ":"xwa"
    ]
    
    private static let kanaPunctToAscii: [Character: String] = [
        "。":".","、":",","！":"!","？":"?","：":":","；":";",
        "（":"(","）":")","「":"[","」":"]","『":"{","』":"}",
        "＋":"+","＊":"*","／":"/","＼":"\\","｜":"|","＾":"^",
        "＝":"=","＿":"_","＠":"@","’":"'","”":"\"","｀":"`",
        "〜":"~","＃":"#","＄":"$","％":"%","＆":"&","＜":"<","＞":">",
        "　":" "
    ]
    
    // Apply sokuon by doubling the first consonant; if none, fall back to "xtu".
    private static func applySokuon(to romaji: String) -> String {
        guard let idx = romaji.firstIndex(where: { $0.isLetter }) else { return "xtu" + romaji }
        let c = romaji[idx]
        if "aeiouAEIOU".contains(c) {
            return "xtu" + romaji
        } else {
            return String(c) + romaji
        }
    }
    
    // Normalize: katakana -> hiragana (preserve 'ー'); leave others intact.
    private static func normalizeToHiragana(_ s: String) -> String {
        return withUTF8Buffer(s) { buffer in
            var out = [UInt8]()
            out.reserveCapacity(buffer.count)
            var index = 0
            let count = buffer.count

            while index < count {
                if let decoded = decodeUTF8Scalar(in: buffer, at: index) {
                    var scalar = decoded.scalar
                    if scalar >= UnicodeScalarConstants.katakanaStart
                        && scalar <= UnicodeScalarConstants.katakanaEnd {
                        scalar -= UnicodeScalarConstants.kanaShift
                    }
                    encodeUTF8Scalar(scalar, into: &out)
                    index += decoded.length
                } else {
                    out.append(buffer[index])
                    index += 1
                }
            }

            return String(decoding: out, as: UTF8.self)
        }
    }
    
    // Peek the first romaji character of the next kana chunk (for deciding "n'").
    private static func peekNextRomajiFirst(hiragana: String, from idx: String.Index) -> Character? {
        guard idx < hiragana.endIndex else { return nil }
        if let j = hiragana.index(idx, offsetBy: 1, limitedBy: hiragana.endIndex), j < hiragana.endIndex {
            let two = String(hiragana[idx...j])
            if let r = kanaToRomajiTwo[two], let f = r.first { return f }
        }
        let one = String(hiragana[idx])
        if let r = kanaToRomajiOne[one], let f = r.first { return f }
        return nil
    }
}
