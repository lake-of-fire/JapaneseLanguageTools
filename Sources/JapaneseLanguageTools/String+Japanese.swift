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
    
    func fromAsciiRepresentation() -> String {
        var result = ""
        var index = startIndex
        
        while index < endIndex {
            // Check for the two-backslash + "U" prefix
            if self[index] == "\\" && self[index...].hasPrefix("\\\\U") {
                // Expecting 11 characters total: "\\" + "U" + 8 hex digits
                let nextIndex = self.index(index, offsetBy: 11, limitedBy: endIndex) ?? endIndex
                let unicodeSegment = self[index..<nextIndex]
                // Drop the first 3 characters ("\\", "\\", and "U")
                let hexDigits = unicodeSegment.dropFirst(3)
                if let scalarValue = UInt32(hexDigits, radix: 16),
                   let scalar = UnicodeScalar(scalarValue) {
                    result.append(Character(scalar))
                    index = nextIndex
                    continue
                }
            }
            result.append(self[index])
            index = self.index(after: index)
        }
        return result
    }
}

fileprivate let katakanaRanges = [
    0x30a1...0x30fa,
    0x30fc...0x30ff,
    0xff66...0xff9d
]

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
fileprivate let kanjiRanges = [(19968, 40959), (13312, 19967), (131072, 173791), (63744, 64255), (194560, 195103)]

public extension StringProtocol {
    var isKana: Bool {
        // https://stackoverflow.com/a/38723951/89373
        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x3041...0x3096, 0x309D...0x309F, // Hiragana ranges
                0x30A1...0x30FA, 0x30FC...0x30FF, // Katakana ranges
                0xFF66...0xFF9D: // Half-width Katakana ranges
                continue
            default:
                return false
            }
        }
        guard !isEmpty else { return false }
        return true
    }
    
    var isKatakana: Bool {
        get {
            if isEmpty { return false }
            // https://stackoverflow.com/a/38723951/89373
            for scalar in unicodeScalars {
                if !katakanaRanges.contains(where: { $0 ~= Int(scalar.value) }) {
                    return false
                }
            }
            return true
        }
    }
    
    var hasKana: Bool {
        get {
            // https://stackoverflow.com/a/38723951/89373
            for scalar in unicodeScalars {
                switch scalar.value {
                case 0x3041...0x3096, 0x309D...0x309F, // Hiragana ranges
                    0x30A1...0x30FA, 0x30FC...0x30FF, // Katakana ranges
                    0xFF66...0xFF9D: // Half-width Katakana ranges
                    return true
                default:
                    continue
                }
            }
            return false
        }
    }
    
    var isKanji: Bool {
        get {
            return (
                !unicodeScalars.isEmpty
                && unicodeScalars.allSatisfy {
                    for (from, to) in kanjiRanges {
                        if $0.value >= UInt32(from) && $0.value <= UInt32(to) {
                            return true
                        }
                    }
                    return false
                }
            )
        }
    }
    
    var hasKanji: Bool {
        get {
            for scalar in unicodeScalars {
                for (from, to) in kanjiRanges {
                    if scalar.value >= UInt32(from) && scalar.value <= UInt32(to) {
                        return true
                    }
                }
            }
            return false
        }
    }
    
    var distinctKanji: Set<String> {
        var result = Set<String>()
        var bytes = Array(utf8)
        var i = 0
        while i < bytes.count {
            if i + 2 < bytes.count,
               (bytes[i] & 0xF0) == 0xE0,
               (bytes[i+1] & 0xC0) == 0x80,
               (bytes[i+2] & 0xC0) == 0x80 {
                let scalar = (UInt32(bytes[i] & 0x0F) << 12) |
                (UInt32(bytes[i+1] & 0x3F) << 6) |
                (UInt32(bytes[i+2] & 0x3F))
                for (from, to) in kanjiRanges {
                    if scalar >= from && scalar <= to {
                        let char = String(decoding: bytes[i...i+2], as: UTF8.self)
                        result.insert(char)
                        break
                    }
                }
                i += 3
            } else {
                i += 1
            }
        }
        return result
    }
    
    var withHiraganaToKatakana: String {
        var result = [UInt8]()
        let bytes = Array(self.utf8)
        var i = 0
        while i < bytes.count {
            if i + 2 < bytes.count,
               bytes[i] == 0xE3,
               (bytes[i+1] & 0xC0) == 0x80,
               (bytes[i+2] & 0xC0) == 0x80 {
                let scalar = (UInt32(bytes[i] & 0x0F) << 12) |
                (UInt32(bytes[i+1] & 0x3F) << 6)  |
                (UInt32(bytes[i+2] & 0x3F))
                if scalar >= 0x3041 && scalar <= 0x3096 {
                    let newScalar = scalar + 0x60
                    let b0 = UInt8(0xE0 | (newScalar >> 12))
                    let b1 = UInt8(0x80 | ((newScalar >> 6) & 0x3F))
                    let b2 = UInt8(0x80 | (newScalar & 0x3F))
                    result.append(contentsOf: [b0, b1, b2])
                    i += 3
                    continue
                }
            }
            result.append(bytes[i])
            i += 1
        }
        return String(decoding: result, as: UTF8.self)
    }
    
    var withKatakanaToHiragana: String {
        var result = [UInt8]()
        let bytes = Array(self.utf8)
        var i = 0
        while i < bytes.count {
            if i + 2 < bytes.count,
               bytes[i] == 0xE3,
               (bytes[i+1] & 0xC0) == 0x80,
               (bytes[i+2] & 0xC0) == 0x80 {
                let scalar = (UInt32(bytes[i] & 0x0F) << 12) |
                (UInt32(bytes[i+1] & 0x3F) << 6)  |
                (UInt32(bytes[i+2] & 0x3F))
                if scalar >= 0x30A1 && scalar <= 0x30F6 {
                    let newScalar = scalar - 0x60
                    let b0 = UInt8(0xE0 | (newScalar >> 12))
                    let b1 = UInt8(0x80 | ((newScalar >> 6) & 0x3F))
                    let b2 = UInt8(0x80 | (newScalar & 0x3F))
                    result.append(contentsOf: [b0, b1, b2])
                    i += 3
                    continue
                }
            }
            result.append(bytes[i])
            i += 1
        }
        return String(decoding: result, as: UTF8.self)
    }
    
    var containsHalfWidthDigits: Bool {
        for byte in self.utf8 {
            // ASCII '0' = 0x30, '9' = 0x39
            if byte >= 0x30 && byte <= 0x39 {
                return true
            }
        }
        return false
    }
    
    var withHalfWidthDigitsToFullWidth: String {
        let fullwidthDigits: [[UInt8]] = [
            [0xEF, 0xBC, 0x90], // '0' -> '０'
            [0xEF, 0xBC, 0x91], // '1' -> '１'
            [0xEF, 0xBC, 0x92], // '2' -> '２'
            [0xEF, 0xBC, 0x93], // '3' -> '３'
            [0xEF, 0xBC, 0x94], // '4' -> '４'
            [0xEF, 0xBC, 0x95], // '5' -> '５'
            [0xEF, 0xBC, 0x96], // '6' -> '６'
            [0xEF, 0xBC, 0x97], // '7' -> '７'
            [0xEF, 0xBC, 0x98], // '8' -> '８'
            [0xEF, 0xBC, 0x99]  // '9' -> '９'
        ]
        
        var resultBytes = [UInt8]()
        resultBytes.reserveCapacity(self.utf8.count)
        
        for byte in self.utf8 {
            // ASCII '0' to '9'
            if byte >= 0x30 && byte <= 0x39 {
                let index = Int(byte - 0x30)
                resultBytes.append(contentsOf: fullwidthDigits[index])
            } else {
                // Non-digit byte - pass through
                resultBytes.append(byte)
            }
        }
        
        return String(decoding: resultBytes, as: UTF8.self)
    }
}
