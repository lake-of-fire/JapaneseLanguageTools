public func containsCJKCharacters(text: String, includingKana: Bool = true, includingNumbers: Bool = false) -> Bool {
    return text.unicodeScalars.contains { scalar in
        var cjkRanges: [ClosedRange<UInt32>] = [
            0x4E00...0x9FFF,   // main block
            0x3400...0x4DBF,   // extended block A
            0x20000...0x2A6DF, // extended block B
            0x2A700...0x2B73F, // extended block C
        ]
        if includingKana {
            let kanaRanges: [ClosedRange<UInt32>] = [
                0x3040...0x309F,   // hiragana
                0x30A0...0x30FF,   // katakana
                0xFF66...0xFF9D,   // half-width katakana
            ]
            cjkRanges.insert(contentsOf: kanaRanges, at: 0)
        }
        if includingNumbers {
            cjkRanges.append(0xFF10...0xFF19) // 0-9 full-width
            cjkRanges.append(0x0030...0x0039) // 0-9
        }
        return cjkRanges.contains { $0.contains(scalar.value) }
    }
}
