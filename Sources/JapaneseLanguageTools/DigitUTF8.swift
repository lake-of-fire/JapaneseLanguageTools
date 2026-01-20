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
func isASCIIOrFullWidthDigitsOnlyUTF8Buffer(_ buffer: UnsafeBufferPointer<UInt8>) -> Bool {
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

@inline(__always)
func isASCIIOrFullWidthDigitsOnlyUTF8Bytes<S: Sequence>(_ bytes: S) -> Bool where S.Element == UInt8 {
    var state = 0

    for b in bytes {
        switch state {
        case 0:
            if b <= DigitUTF8Constants.asciiMax {
                if b < DigitUTF8Constants.asciiZero || b > DigitUTF8Constants.asciiNine {
                    return false
                }
            } else if b == DigitUTF8Constants.fullWidthDigitLead0 {
                state = 1
            } else {
                return false
            }
        case 1:
            if b == DigitUTF8Constants.fullWidthDigitLead1 {
                state = 2
            } else {
                return false
            }
        default:
            if b >= DigitUTF8Constants.fullWidthDigitZero && b <= DigitUTF8Constants.fullWidthDigitNine {
                state = 0
            } else {
                return false
            }
        }
    }

    return state == 0
}
