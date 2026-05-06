import Foundation

public func containsCJKCharacters(text: String, includingKana: Bool = true, includingNumbers: Bool = false) -> Bool {
    guard !text.isEmpty else { return false }
    if let result = text.utf8.withContiguousStorageIfAvailable({ buffer in
        containsCJKCharactersUTF8Buffer(buffer, includingKana: includingKana, includingNumbers: includingNumbers)
    }) {
        return result
    }
    var utf8Bytes = Array(text.utf8)
    return utf8Bytes.withUnsafeBufferPointer { buffer in
        containsCJKCharactersUTF8Buffer(buffer, includingKana: includingKana, includingNumbers: includingNumbers)
    }
}

@inline(__always)
private func containsCJKCharactersUTF8Buffer(
    _ buffer: UnsafeBufferPointer<UInt8>,
    includingKana: Bool,
    includingNumbers: Bool
) -> Bool {
    var index = 0
    let count = buffer.count

    while index < count {
        let byte0 = buffer[index]
        if byte0 < 0x80 {
            if includingNumbers, byte0 >= 0x30, byte0 <= 0x39 {
                return true
            }
            index += 1
            continue
        }

        var scalar: UInt32 = 0
        if byte0 < 0xE0 {
            if index + 1 >= count { break }
            let byte1 = buffer[index + 1]
            if (byte1 & 0xC0) != 0x80 {
                index += 1
                continue
            }
            scalar = (UInt32(byte0 & 0x1F) << 6) | UInt32(byte1 & 0x3F)
            index += 2
        } else if byte0 < 0xF0 {
            if index + 2 >= count { break }
            let byte1 = buffer[index + 1]
            let byte2 = buffer[index + 2]
            if (byte1 & 0xC0) != 0x80 || (byte2 & 0xC0) != 0x80 {
                index += 1
                continue
            }
            scalar = (UInt32(byte0 & 0x0F) << 12)
                | (UInt32(byte1 & 0x3F) << 6)
                | UInt32(byte2 & 0x3F)
            index += 3
        } else if byte0 < 0xF8 {
            if index + 3 >= count { break }
            let byte1 = buffer[index + 1]
            let byte2 = buffer[index + 2]
            let byte3 = buffer[index + 3]
            if (byte1 & 0xC0) != 0x80 || (byte2 & 0xC0) != 0x80 || (byte3 & 0xC0) != 0x80 {
                index += 1
                continue
            }
            scalar = (UInt32(byte0 & 0x07) << 18)
                | (UInt32(byte1 & 0x3F) << 12)
                | (UInt32(byte2 & 0x3F) << 6)
                | UInt32(byte3 & 0x3F)
            index += 4
        } else {
            index += 1
            continue
        }

        if containsCJKScalar(scalar, includingKana: includingKana, includingNumbers: includingNumbers) {
            return true
        }
    }

    return false
}

@inline(__always)
private func containsCJKScalar(_ scalar: UInt32, includingKana: Bool, includingNumbers: Bool) -> Bool {
    if scalar >= 0x4E00 && scalar <= 0x9FFF { return true }
    if scalar >= 0x3400 && scalar <= 0x4DBF { return true }
    if scalar >= 0x20000 && scalar <= 0x2A6DF { return true }
    if scalar >= 0x2A700 && scalar <= 0x2B73F { return true }

    if includingKana {
        if scalar >= 0x3040 && scalar <= 0x309F { return true }
        if scalar >= 0x30A0 && scalar <= 0x30FF { return true }
        if scalar >= 0xFF66 && scalar <= 0xFF9D { return true }
    }

    if includingNumbers {
        if scalar >= 0xFF10 && scalar <= 0xFF19 { return true }
    }

    return false
}

private let rendakuTransforms = [
    "か" : ["が"],
    "き" : ["ぎ"],
    "く" : ["ぐ"],
    "け" : ["げ"],
    "こ" : ["ご"],
    "さ" : ["ざ"],
    "し" : ["じ"],
    "す" : ["ず"],
    "せ" : ["ぜ"],
    "そ" : ["ぞ"],
    "た" : ["だ"],
    "ち" : ["ぢ", "じ"],
    "つ" : ["づ", "ず"],
    "て" : ["で"],
    "と" : ["ど"],
    "は" : ["ば", "ぱ"],
    "ひ" : ["び", "ぴ"],
    "ふ" : ["ぶ", "ぷ"],
    "へ" : ["べ", "ぺ"],
    "ほ" : ["ぼ", "ぽ"]
]

public extension String {
    var isASCIIOrFullWidthDigitsOnly: Bool {
        guard !isEmpty else { return false }
        if let result = utf8.withContiguousStorageIfAvailable({ buffer in
            isASCIIOrFullWidthDigitsOnlyUTF8Buffer(buffer)
        }) {
            return result
        }
        return isASCIIOrFullWidthDigitsOnlyUTF8Bytes(utf8)
    }
}

/// Requires preceding character to be kana, kanji or numeric.
public func rendakuVariations(wordKana: String, accumulatedOutputText: String) -> [String] {
    guard
        let lastAccumulatedCharacter = accumulatedOutputText.last,
        containsCJKCharacters(text: String(lastAccumulatedCharacter), includingKana: true, includingNumbers: true)
            || (String(lastAccumulatedCharacter).rangeOfCharacter(from: CharacterSet.decimalDigits) != nil),
        let firstCharacter = wordKana.first,
        let transforms = rendakuTransforms[String(firstCharacter)]
    else { return [] }
    return transforms.map { wordKana.replacingCharacters(in: ...$0.utf16.startIndex, with: $0) }
}
