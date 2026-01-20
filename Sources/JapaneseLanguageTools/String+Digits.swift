import Foundation

public extension StringProtocol {
    var isASCIIOrFullWidthDigitsOnly: Bool {
        if let result = utf8.withContiguousStorageIfAvailable({ buffer in
            isASCIIOrFullWidthDigitsOnlyUTF8Buffer(buffer)
        }) {
            return result
        }
        return isASCIIOrFullWidthDigitsOnlyUTF8Bytes(utf8)
    }
}
