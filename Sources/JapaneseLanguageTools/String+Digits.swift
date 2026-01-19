import Foundation

private enum DigitUTF8Constants {
    static let asciiMax: UInt8 = 0x7F
    static let asciiZero: UInt8 = 0x30
    static let asciiNine: UInt8 = 0x39
    static let fullWidthDigitLead0: UInt8 = 0xEF
    static let fullWidthDigitLead1: UInt8 = 0xBC
    static let fullWidthDigitZero: UInt8 = 0x90
    static let fullWidthDigitNine: UInt8 = 0x99
}

@inline(__always)
private func isASCIIOrFullWidthDigitsOnlyBuffer(_ buffer: UnsafeBufferPointer<UInt8>) -> Bool {
    var index = 0
    let count = buffer.count

    while index < count {
        let b0 = buffer[index]
        if b0 <= DigitUTF8Constants.asciiMax {
            if b0 < DigitUTF8Constants.asciiZero || b0 > DigitUTF8Constants.asciiNine {
                return false
            }
            index += 1
            continue
        }

        if index + 2 < count,
           b0 == DigitUTF8Constants.fullWidthDigitLead0,
           buffer[index + 1] == DigitUTF8Constants.fullWidthDigitLead1 {
            let b2 = buffer[index + 2]
            if b2 >= DigitUTF8Constants.fullWidthDigitZero
                && b2 <= DigitUTF8Constants.fullWidthDigitNine {
                index += 3
                continue
            }
        }

        return false
    }

    return true
}

public extension StringProtocol {
    var isASCIIOrFullWidthDigitsOnly: Bool {
        if let result = utf8.withContiguousStorageIfAvailable({ buffer in
            isASCIIOrFullWidthDigitsOnlyBuffer(buffer)
        }) {
            return result
        }
        var bytes = Array(utf8)
        return bytes.withUnsafeBufferPointer { buffer in
            isASCIIOrFullWidthDigitsOnlyBuffer(buffer)
        }
    }
}
