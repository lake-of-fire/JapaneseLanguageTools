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
    static let katakanaPhoneticExtensionsStart: UInt32 = 0x31F0
    static let katakanaPhoneticExtensionsEnd: UInt32 = 0x31FF

    static let halfWidthKatakanaStart: UInt32 = 0xFF66
    static let halfWidthKatakanaEnd: UInt32 = 0xFF9D

    static let hiraganaIterationMark: UInt32 = 0x309D // ゝ
    static let voicedHiraganaIterationMark: UInt32 = 0x309E // ゞ
    static let katakanaIterationMark: UInt32 = 0x30FD // ヽ
    static let voicedKatakanaIterationMark: UInt32 = 0x30FE // ヾ
    static let combiningVoicedSoundMark: UInt32 = 0x3099 // Combining dakuten: ゙
    static let combiningSemiVoicedSoundMark: UInt32 = 0x309A // Combining handakuten: ゚

    static let kanaShift: UInt32 = 0x60

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

    static let kanjiThreeByteLeadMin: UInt8 = 0xE3
    static let kanjiThreeByteLeadMax: UInt8 = 0xEF
    static let kanjiCommonLeadMax: UInt8 = 0xE9
    static let kanjiCompatibilityLead: UInt8 = 0xEF
    static let kanjiFourByteLead: UInt8 = 0xF0

    static let byteMask: UInt32 = 0xFF

    static let reverseSolidus: UInt8 = 0x5C // "\\"
    static let uppercaseU: UInt8 = 0x55 // "U"
    static let hexNibbleMask: UInt32 = 0xF
    static let hexDigitRadix: UInt8 = 10
    static let bitsPerHexDigit = 4
}

@inline(__always)
private func withUTF8Buffer<S: StringProtocol, R>(_ string: S, _ body: (UnsafeBufferPointer<UInt8>) -> R) -> R {
    if let result = string.utf8.withContiguousStorageIfAvailable({ buffer in
        body(buffer)
    }) {
        return result
    }
    let bytes = Array(string.utf8)
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
    isJapaneseKanaScalar(scalar)
}

@inline(__always)
public func isJapaneseKanaScalar(_ scalar: UInt32) -> Bool {
    if scalar >= UnicodeScalarConstants.hiraganaStart && scalar <= UnicodeScalarConstants.hiraganaEnd { return true }
    if scalar >= UnicodeScalarConstants.hiraganaIterationStart && scalar <= UnicodeScalarConstants.hiraganaIterationEnd { return true }
    if scalar >= UnicodeScalarConstants.katakanaStart && scalar <= UnicodeScalarConstants.katakanaEnd { return true }
    if scalar >= UnicodeScalarConstants.katakanaProlongedStart && scalar <= UnicodeScalarConstants.katakanaProlongedEnd { return true }
    if scalar >= UnicodeScalarConstants.katakanaPhoneticExtensionsStart && scalar <= UnicodeScalarConstants.katakanaPhoneticExtensionsEnd { return true }
    if scalar >= UnicodeScalarConstants.halfWidthKatakanaStart && scalar <= UnicodeScalarConstants.halfWidthKatakanaEnd { return true }
    return false
}

@inline(__always)
public func isJapaneseKanaScalar(_ scalar: UnicodeScalar) -> Bool {
    isJapaneseKanaScalar(scalar.value)
}

@inline(__always)
public func isJapaneseKanaCharacterFast(_ character: Character) -> Bool {
    let stringValue = String(character)
    return withUTF8Buffer(stringValue) { buffer in
        guard !buffer.isEmpty else { return false }
        return allUTF8ScalarsSatisfy(in: buffer) { isJapaneseKanaScalar($0) }
    }
}

@inline(__always)
private func isKatakanaScalar(_ scalar: UInt32) -> Bool {
    if scalar >= UnicodeScalarConstants.katakanaStart && scalar <= UnicodeScalarConstants.katakanaEnd { return true }
    if scalar >= UnicodeScalarConstants.katakanaProlongedStart && scalar <= UnicodeScalarConstants.katakanaProlongedEnd { return true }
    if scalar >= UnicodeScalarConstants.halfWidthKatakanaStart && scalar <= UnicodeScalarConstants.halfWidthKatakanaEnd { return true }
    return false
}

public extension StringProtocol where Self: RangeReplaceableCollection {
    var asciiRepresentation: String {
        withUTF8Buffer(self) { buffer in
            guard buffer.contains(where: { $0 > UTF8Constants.asciiMax }) else {
                return String(decoding: buffer, as: UTF8.self)
            }

            var output = [UInt8]()
            output.reserveCapacity(buffer.count * 4)
            var index = 0
            while index < buffer.count {
                let byte = buffer[index]
                if byte <= UTF8Constants.asciiMax {
                    output.append(byte)
                    index += 1
                    continue
                }

                guard let decoded = decodeUTF8Scalar(in: buffer, at: index) else {
                    index += 1
                    continue
                }
                output.append(UTF8Constants.reverseSolidus)
                output.append(UTF8Constants.reverseSolidus)
                output.append(UTF8Constants.uppercaseU)
                for shift in stride(
                    from: (UnicodeScalarConstants.unicodeScalarHexWidth - 1) * UTF8Constants.bitsPerHexDigit,
                    through: 0,
                    by: -UTF8Constants.bitsPerHexDigit
                ) {
                    let nibble = UInt8((decoded.scalar >> UInt32(shift)) & UTF8Constants.hexNibbleMask)
                    output.append(
                        nibble < UTF8Constants.hexDigitRadix
                            ? UTF8Constants.asciiZero + nibble
                            : UTF8Constants.asciiUppercaseA + nibble - UTF8Constants.hexDigitRadix
                    )
                }
                index += decoded.length
            }
            return String(decoding: output, as: UTF8.self)
        }
    }

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

@inline(__always)
private func mayContainKanjiUTF8(_ buffer: UnsafeBufferPointer<UInt8>) -> Bool {
    for byte in buffer {
        if (byte >= UTF8Constants.kanjiThreeByteLeadMin && byte <= UTF8Constants.kanjiCommonLeadMax)
            || byte == UTF8Constants.kanjiCompatibilityLead
            || byte == UTF8Constants.kanjiFourByteLead {
            return true
        }
    }
    return false
}

private struct UTF8KanjiBytes: Hashable {
    let packedBytes: UInt32
    let length: Int
}

@inline(__always)
private func packedUTF8Bytes(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8) -> UInt32 {
    (UInt32(b0) << 16) | (UInt32(b1) << 8) | UInt32(b2)
}

@inline(__always)
private func packedUTF8Bytes(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> UInt32 {
    (UInt32(b0) << 24) | (UInt32(b1) << 16) | (UInt32(b2) << 8) | UInt32(b3)
}

@inline(__always)
private func kanjiBytes(in buffer: UnsafeBufferPointer<UInt8>, at index: Int) -> UTF8KanjiBytes? {
    let count = buffer.count
    let byte0 = buffer[index]

    if byte0 >= UTF8Constants.kanjiThreeByteLeadMin && byte0 <= UTF8Constants.kanjiThreeByteLeadMax {
        guard index + 2 < count else { return nil }
        let byte1 = buffer[index + 1]
        let byte2 = buffer[index + 2]
        guard isContinuationByte(byte1), isContinuationByte(byte2) else { return nil }

        let scalar = (UInt32(byte0 & UTF8Constants.threeByteLeadMask) << 12)
            | (UInt32(byte1 & UTF8Constants.sixBitMask) << 6)
            | UInt32(byte2 & UTF8Constants.sixBitMask)
        if isJapaneseKanjiScalar(scalar) {
            return UTF8KanjiBytes(packedBytes: packedUTF8Bytes(byte0, byte1, byte2), length: 3)
        }
        return nil
    }

    if byte0 == UTF8Constants.kanjiFourByteLead {
        guard index + 3 < count else { return nil }
        let byte1 = buffer[index + 1]
        let byte2 = buffer[index + 2]
        let byte3 = buffer[index + 3]
        guard isContinuationByte(byte1), isContinuationByte(byte2), isContinuationByte(byte3) else { return nil }

        let scalar = (UInt32(byte0 & UTF8Constants.fourByteLeadMask) << 18)
            | (UInt32(byte1 & UTF8Constants.sixBitMask) << 12)
            | (UInt32(byte2 & UTF8Constants.sixBitMask) << 6)
            | UInt32(byte3 & UTF8Constants.sixBitMask)
        if isJapaneseKanjiScalar(scalar) {
            return UTF8KanjiBytes(packedBytes: packedUTF8Bytes(byte0, byte1, byte2, byte3), length: 4)
        }
    }

    return nil
}

@inline(__always)
private func string(fromKanjiBytes bytes: UTF8KanjiBytes) -> String {
    if bytes.length == 3 {
        return String(decoding: [
            UInt8((bytes.packedBytes >> 16) & UTF8Constants.byteMask),
            UInt8((bytes.packedBytes >> 8) & UTF8Constants.byteMask),
            UInt8(bytes.packedBytes & UTF8Constants.byteMask)
        ], as: UTF8.self)
    }
    return String(decoding: [
        UInt8((bytes.packedBytes >> 24) & UTF8Constants.byteMask),
        UInt8((bytes.packedBytes >> 16) & UTF8Constants.byteMask),
        UInt8((bytes.packedBytes >> 8) & UTF8Constants.byteMask),
        UInt8(bytes.packedBytes & UTF8Constants.byteMask)
    ], as: UTF8.self)
}

/// Unicode 17 CJK ideograph blocks, shared by scalar, UTF-8 and ruby callers.
/// https://www.unicode.org/Public/17.0.0/ucd/Blocks.txt
@inlinable
@inline(__always)
public func isJapaneseKanjiScalar(_ scalar: UInt32) -> Bool {
    switch scalar {
    case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF,
         0x2A700...0x2EE5F, // Adjacent extensions C, D, E, F, I
         0x30000...0x3347F, // Adjacent extensions G, H, J
         0xF900...0xFAFF, 0x2F800...0x2FA1F:
        return true
    default:
        return false
    }
}

@inlinable
@inline(__always)
public func isJapaneseKanjiScalar(_ scalar: UnicodeScalar) -> Bool {
    isJapaneseKanjiScalar(scalar.value)
}

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

    var hasKatakana: Bool {
        return withUTF8Buffer(self) { buffer in
            containsUTF8Scalar(in: buffer) { isKatakanaScalar($0) }
        }
    }

    func expandingJapaneseKanaIterationMarks() -> String? {
        withUTF8Buffer(self) { buffer in
            let containsIterationMark = containsUTF8Scalar(in: buffer) { scalar in
                scalar == UnicodeScalarConstants.hiraganaIterationMark
                    || scalar == UnicodeScalarConstants.voicedHiraganaIterationMark
                    || scalar == UnicodeScalarConstants.katakanaIterationMark
                    || scalar == UnicodeScalarConstants.voicedKatakanaIterationMark
            }
            guard containsIterationMark else { return nil }

            var result = [UInt8]()
            result.reserveCapacity(buffer.count)
            var previousKanaRange: Range<Int>?
            var index = 0
            let count = buffer.count

            while index < count {
                guard let decoded = decodeUTF8Scalar(in: buffer, at: index) else {
                    result.append(buffer[index])
                    previousKanaRange = nil
                    index += 1
                    continue
                }

                switch decoded.scalar {
                case UnicodeScalarConstants.hiraganaIterationMark,
                     UnicodeScalarConstants.katakanaIterationMark,
                     UnicodeScalarConstants.voicedHiraganaIterationMark,
                     UnicodeScalarConstants.voicedKatakanaIterationMark:
                    guard let previousKanaRange else { return nil }
                    var voiced = decoded.scalar == UnicodeScalarConstants.voicedHiraganaIterationMark
                        || decoded.scalar == UnicodeScalarConstants.voicedKatakanaIterationMark
                    // ゞ and ヾ canonically decompose to the unvoiced mark + dakuten.
                    // Consume that token together so the source range stays on the kana.
                    let nextIndex = index + decoded.length
                    if !voiced, nextIndex < count,
                       let next = decodeUTF8Scalar(in: buffer, at: nextIndex),
                       next.scalar == UnicodeScalarConstants.combiningVoicedSoundMark {
                        voiced = true
                        index += next.length
                    }
                    // The mark selects the repeated syllable's voicing, independently
                    // of dakuten or handakuten on the source syllable (NFC or NFD).
                    // Unicode 17, sections 18.4.1 and 18.4.2.
                    let previous = String(decoding: buffer[previousKanaRange], as: UTF8.self)
                    var repeated = String.UnicodeScalarView()
                    for scalar in previous.decomposedStringWithCanonicalMapping.unicodeScalars
                    where scalar.value != UnicodeScalarConstants.combiningVoicedSoundMark
                        && scalar.value != UnicodeScalarConstants.combiningSemiVoicedSoundMark {
                        repeated.append(scalar)
                    }
                    if voiced {
                        repeated.append(UnicodeScalar(UnicodeScalarConstants.combiningVoicedSoundMark)!)
                    }
                    result.append(contentsOf: String(repeated).precomposedStringWithCanonicalMapping.utf8)
                default:
                    for offset in 0..<decoded.length {
                        result.append(buffer[index + offset])
                    }
                    let decodedEnd = index + decoded.length
                    if decoded.scalar == UnicodeScalarConstants.combiningVoicedSoundMark
                        || decoded.scalar == UnicodeScalarConstants.combiningSemiVoicedSoundMark {
                        if let existingRange = previousKanaRange, existingRange.upperBound == index {
                            previousKanaRange = existingRange.lowerBound..<decodedEnd
                        }
                    } else {
                        previousKanaRange = isJapaneseKanaScalar(decoded.scalar) ? index..<decodedEnd : nil
                    }
                }
                index += decoded.length
            }

            return String(decoding: result, as: UTF8.self)
        }
    }

    var isKanji: Bool {
        guard !isEmpty else { return false }
        return withUTF8Buffer(self) { buffer in
            allUTF8ScalarsSatisfy(in: buffer) { scalar in
                isJapaneseKanjiScalar(scalar)
            }
        }
    }

    var hasKanji: Bool {
        return withUTF8Buffer(self) { buffer in
            containsUTF8Scalar(in: buffer) { scalar in
                isJapaneseKanjiScalar(scalar)
            }
        }
    }

    var kanjiCount: Int {
        var count = 0
        withUTF8Buffer(self) { buffer in
            forEachUTF8Scalar(in: buffer) { scalar in
                if isJapaneseKanjiScalar(scalar) {
                    count += 1
                }
            }
        }
        return count
    }

    var distinctKanji: Set<String> {
        var seen = Set<UTF8KanjiBytes>()
        withUTF8Buffer(self) { buffer in
            guard mayContainKanjiUTF8(buffer) else { return }
            var index = 0
            while index < buffer.count {
                if let kanjiBytes = kanjiBytes(in: buffer, at: index) {
                    seen.insert(kanjiBytes)
                    index += kanjiBytes.length
                } else {
                    index += 1
                }
            }
        }
        var result = Set<String>()
        result.reserveCapacity(seen.count)
        for bytes in seen {
            result.insert(string(fromKanjiBytes: bytes))
        }
        return result
    }

    var orderedDistinctKanji: [String] {
        var result = [String]()
        var seen = Set<UTF8KanjiBytes>()
        withUTF8Buffer(self) { buffer in
            guard mayContainKanjiUTF8(buffer) else { return }
            var index = 0
            while index < buffer.count {
                if let kanjiBytes = kanjiBytes(in: buffer, at: index) {
                    if seen.insert(kanjiBytes).inserted {
                        result.append(string(fromKanjiBytes: kanjiBytes))
                    }
                    index += kanjiBytes.length
                } else {
                    index += 1
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
            let containsConvertibleHiragana = containsUTF8Scalar(in: buffer) { scalar in
                scalar >= UnicodeScalarConstants.hiraganaStart
                    && scalar <= UnicodeScalarConstants.hiraganaEnd
            }
            guard containsConvertibleHiragana else { return String(self) }

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
            let containsConvertibleKatakana = containsUTF8Scalar(in: buffer) { scalar in
                scalar >= UnicodeScalarConstants.katakanaStart
                    && scalar <= UnicodeScalarConstants.katakanaToHiraganaEnd
            }
            guard containsConvertibleKatakana else { return String(self) }

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
