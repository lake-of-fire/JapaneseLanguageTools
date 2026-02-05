import Foundation

private enum UnicodeScalarConstants {
    static let unicodeScalarHexWidth = 8

    static let hiraganaStart: UInt32 = 0x3041
    static let hiraganaEnd: UInt32 = 0x3096
    static let hiraganaIterationStart: UInt32 = 0x309D
    static let hiraganaIterationEnd: UInt32 = 0x309F

    static let katakanaStart: UInt32 = 0x30A1
    static let katakanaEnd: UInt32 = 0x30FA
    static let katakanaToHiraganaEnd: UInt32 = 0x30F6
    static let katakanaProlongedStart: UInt32 = 0x30FC
    static let katakanaProlongedEnd: UInt32 = 0x30FF

    static let halfWidthKatakanaStart: UInt32 = 0xFF66
    static let halfWidthKatakanaEnd: UInt32 = 0xFF9D

    static let kanaShift: UInt32 = 0x60

    static let kanjiCommonStart: UInt32 = 0x4E00
    static let kanjiCommonEnd: UInt32 = 0x9FFF
    static let kanjiExtensionAStart: UInt32 = 0x3400
    static let kanjiExtensionAEnd: UInt32 = 0x4DFF
    static let kanjiExtensionBStart: UInt32 = 0x20000
    static let kanjiExtensionBEnd: UInt32 = 0x2A6DF
    static let kanjiCompatibilityStart: UInt32 = 0xF900
    static let kanjiCompatibilityEnd: UInt32 = 0xFAFF
    static let kanjiCompatibilitySupplementStart: UInt32 = 0x2F800
    static let kanjiCompatibilitySupplementEnd: UInt32 = 0x2FA1F

    static let fullWidthDigitZero: UInt32 = 0xFF10
    static let fullWidthDigitNine: UInt32 = 0xFF19

    static let utf8TwoByteMaxScalar: UInt32 = 0x7FF
    static let utf8ThreeByteMaxScalar: UInt32 = 0xFFFF
}

private enum UTF8Constants {
    static let asciiMax: UInt8 = 0x7F
    static let asciiZero: UInt8 = 0x30
    static let asciiNine: UInt8 = 0x39
    static let asciiUppercaseA: UInt8 = 0x41
    static let asciiUppercaseZ: UInt8 = 0x5A
    static let asciiLowercaseA: UInt8 = 0x61
    static let asciiLowercaseZ: UInt8 = 0x7A

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

private extension UInt32 {
    var hexa: String { .init(self, radix: 16, uppercase: true) }
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
private func containsASCIILetterUTF8Buffer(_ buffer: UnsafeBufferPointer<UInt8>) -> Bool {
    for byte in buffer {
        if byte >= UTF8Constants.asciiUppercaseA && byte <= UTF8Constants.asciiUppercaseZ {
            return true
        }
        if byte >= UTF8Constants.asciiLowercaseA && byte <= UTF8Constants.asciiLowercaseZ {
            return true
        }
    }
    return false
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
private func forEachUTF8Scalar(in buffer: UnsafeBufferPointer<UInt8>, _ body: (UInt32) -> Void) {
    var index = 0
    let count = buffer.count
    while index < count {
        if let decoded = decodeUTF8Scalar(in: buffer, at: index) {
            body(decoded.scalar)
            index += decoded.length
        } else {
            index += 1
        }
    }
}

@inline(__always)
private func containsUTF8Scalar(in buffer: UnsafeBufferPointer<UInt8>, _ predicate: (UInt32) -> Bool) -> Bool {
    var index = 0
    let count = buffer.count
    while index < count {
        if let decoded = decodeUTF8Scalar(in: buffer, at: index) {
            if predicate(decoded.scalar) { return true }
            index += decoded.length
        } else {
            index += 1
        }
    }
    return false
}

@inline(__always)
private func allUTF8ScalarsSatisfy(in buffer: UnsafeBufferPointer<UInt8>, _ predicate: (UInt32) -> Bool) -> Bool {
    var index = 0
    let count = buffer.count
    while index < count {
        if let decoded = decodeUTF8Scalar(in: buffer, at: index) {
            if !predicate(decoded.scalar) { return false }
            index += decoded.length
        } else {
            return false
        }
    }
    return true
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

@inline(__always)
private func isKanaScalar(_ scalar: UInt32) -> Bool {
    if scalar >= UnicodeScalarConstants.hiraganaStart && scalar <= UnicodeScalarConstants.hiraganaEnd { return true }
    if scalar >= UnicodeScalarConstants.hiraganaIterationStart && scalar <= UnicodeScalarConstants.hiraganaIterationEnd { return true }
    if scalar >= UnicodeScalarConstants.katakanaStart && scalar <= UnicodeScalarConstants.katakanaEnd { return true }
    if scalar >= UnicodeScalarConstants.katakanaProlongedStart && scalar <= UnicodeScalarConstants.katakanaProlongedEnd { return true }
    if scalar >= UnicodeScalarConstants.halfWidthKatakanaStart && scalar <= UnicodeScalarConstants.halfWidthKatakanaEnd { return true }
    return false
}

@inline(__always)
private func isKatakanaScalar(_ scalar: UInt32) -> Bool {
    if scalar >= UnicodeScalarConstants.katakanaStart && scalar <= UnicodeScalarConstants.katakanaEnd { return true }
    if scalar >= UnicodeScalarConstants.katakanaProlongedStart && scalar <= UnicodeScalarConstants.katakanaProlongedEnd { return true }
    if scalar >= UnicodeScalarConstants.halfWidthKatakanaStart && scalar <= UnicodeScalarConstants.halfWidthKatakanaEnd { return true }
    return false
}

private extension Character {
    var hexaValues: [String] {
        var values = [String]()
        let stringValue = String(self)
        withUTF8Buffer(stringValue) { buffer in
            forEachUTF8Scalar(in: buffer) { scalar in
                let hexa = scalar.hexa
                let paddingCount = UnicodeScalarConstants.unicodeScalarHexWidth - hexa.count
                values.append("\\\\U" + String(repeating: "0", count: paddingCount) + hexa)
            }
        }
        return values
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
fileprivate let kanjiRanges: [ClosedRange<UInt32>] = [
    UnicodeScalarConstants.kanjiCommonStart...UnicodeScalarConstants.kanjiCommonEnd,
    UnicodeScalarConstants.kanjiExtensionAStart...UnicodeScalarConstants.kanjiExtensionAEnd,
    UnicodeScalarConstants.kanjiExtensionBStart...UnicodeScalarConstants.kanjiExtensionBEnd,
    UnicodeScalarConstants.kanjiCompatibilityStart...UnicodeScalarConstants.kanjiCompatibilityEnd,
    UnicodeScalarConstants.kanjiCompatibilitySupplementStart...UnicodeScalarConstants.kanjiCompatibilitySupplementEnd
]

public extension StringProtocol {
    var isKana: Bool {
        guard !isEmpty else { return false }
        return withUTF8Buffer(self) { buffer in
            allUTF8ScalarsSatisfy(in: buffer) { isKanaScalar($0) }
        }
    }

    var isKatakana: Bool {
        if isEmpty { return false }
        return withUTF8Buffer(self) { buffer in
            allUTF8ScalarsSatisfy(in: buffer) { isKatakanaScalar($0) }
        }
    }

    var hasKana: Bool {
        return withUTF8Buffer(self) { buffer in
            containsUTF8Scalar(in: buffer) { isKanaScalar($0) }
        }
    }

    var isKanji: Bool {
        guard !isEmpty else { return false }
        return withUTF8Buffer(self) { buffer in
            allUTF8ScalarsSatisfy(in: buffer) { scalar in
                kanjiRanges.contains { $0.contains(scalar) }
            }
        }
    }

    var hasKanji: Bool {
        return withUTF8Buffer(self) { buffer in
            containsUTF8Scalar(in: buffer) { scalar in
                kanjiRanges.contains { $0.contains(scalar) }
            }
        }
    }

    var distinctKanji: Set<String> {
        var result = Set<String>()
        withUTF8Buffer(self) { buffer in
            forEachUTF8Scalar(in: buffer) { scalar in
                if kanjiRanges.contains(where: { $0.contains(scalar) }),
                   let unicodeScalar = UnicodeScalar(scalar) {
                    result.insert(String(unicodeScalar))
                }
            }
        }
        return result
    }

    var hasASCIILetters: Bool {
        return withUTF8Buffer(self) { buffer in
            containsASCIILetterUTF8Buffer(buffer)
        }
    }

    var withHiraganaToKatakana: String {
        return withUTF8Buffer(self) { buffer in
            var result = [UInt8]()
            result.reserveCapacity(buffer.count)
            var index = 0
            let count = buffer.count

            while index < count {
                if let decoded = decodeUTF8Scalar(in: buffer, at: index) {
                    if decoded.scalar >= UnicodeScalarConstants.hiraganaStart
                        && decoded.scalar <= UnicodeScalarConstants.hiraganaEnd {
                        let newScalar = decoded.scalar + UnicodeScalarConstants.kanaShift
                        encodeUTF8Scalar(newScalar, into: &result)
                    } else {
                        for offset in 0..<decoded.length {
                            result.append(buffer[index + offset])
                        }
                    }
                    index += decoded.length
                } else {
                    result.append(buffer[index])
                    index += 1
                }
            }
            return String(decoding: result, as: UTF8.self)
        }
    }

    var withKatakanaToHiragana: String {
        return withUTF8Buffer(self) { buffer in
            var result = [UInt8]()
            result.reserveCapacity(buffer.count)
            var index = 0
            let count = buffer.count

            while index < count {
                if let decoded = decodeUTF8Scalar(in: buffer, at: index) {
                    if decoded.scalar >= UnicodeScalarConstants.katakanaStart
                        && decoded.scalar <= UnicodeScalarConstants.katakanaToHiraganaEnd {
                        let newScalar = decoded.scalar - UnicodeScalarConstants.kanaShift
                        encodeUTF8Scalar(newScalar, into: &result)
                    } else {
                        for offset in 0..<decoded.length {
                            result.append(buffer[index + offset])
                        }
                    }
                    index += decoded.length
                } else {
                    result.append(buffer[index])
                    index += 1
                }
            }
            return String(decoding: result, as: UTF8.self)
        }
    }

    var containsHalfWidthDigits: Bool {
        for byte in self.utf8 {
            if byte >= UTF8Constants.asciiZero && byte <= UTF8Constants.asciiNine {
                return true
            }
        }
        return false
    }

    var withHalfWidthDigitsToFullWidth: String {
        var resultBytes = [UInt8]()
        resultBytes.reserveCapacity(self.utf8.count)

        for byte in self.utf8 {
            if byte >= UTF8Constants.asciiZero && byte <= UTF8Constants.asciiNine {
                let scalar = UnicodeScalarConstants.fullWidthDigitZero + UInt32(byte - UTF8Constants.asciiZero)
                encodeUTF8Scalar(scalar, into: &resultBytes)
            } else {
                resultBytes.append(byte)
            }
        }

        return String(decoding: resultBytes, as: UTF8.self)
    }
}
