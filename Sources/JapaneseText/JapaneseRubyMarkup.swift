import Foundation

/// Classifies kana after composing decomposed and half-width voicing marks.
/// This comparison does not rewrite the authored display spelling.
public func isJapaneseRubyKana(_ text: String) -> Bool {
    text.precomposedStringWithCompatibilityMapping.precomposedStringWithCanonicalMapping.isKana
}

/// Folds kana graphemes for phonetic comparisons while preserving literal
/// symbols and compatibility kanji in their authored representation.
public func japaneseRubyKanaComparisonKey(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.utf8.count)
    for character in text {
        let authored = String(character)
        let composed = authored.precomposedStringWithCompatibilityMapping.precomposedStringWithCanonicalMapping
        result += composed.isKana ? composed.withKatakanaToHiragana : authored
    }
    return result
}

public struct JapaneseRubyAnnotationAlignment: Equatable, Sendable {
    public let surfacePrefix: String
    public let rubySurface: String
    public let rubyReading: String
    public let surfaceSuffix: String
}

public func alignJapaneseRubyAnnotation(
    surface: String,
    reading: String,
    normalizeReadingToHiragana: Bool = true
) -> JapaneseRubyAnnotationAlignment? {
    let normalizedReading = normalizeReadingToHiragana && !isJapaneseRubyKana(surface)
        ? reading.withKatakanaToHiragana
        : reading
    guard !surface.isEmpty,
          !normalizedReading.isEmpty,
          surface != normalizedReading,
          !isJapaneseRubyKana(surface),
          surface.hasKanji else {
        return nil
    }

    var surfaceStart = surface.startIndex
    var readingStart = normalizedReading.startIndex
    while surfaceStart < surface.endIndex,
          readingStart < normalizedReading.endIndex,
          japaneseRubyKanaComparisonKey(String(surface[surfaceStart]))
            == japaneseRubyKanaComparisonKey(String(normalizedReading[readingStart])) {
        surfaceStart = surface.index(after: surfaceStart)
        readingStart = normalizedReading.index(after: readingStart)
    }

    var surfaceEnd = surface.endIndex
    var readingEnd = normalizedReading.endIndex
    while surfaceStart < surfaceEnd,
          readingStart < readingEnd {
        let previousSurfaceIndex = surface.index(before: surfaceEnd)
        let previousReadingIndex = normalizedReading.index(before: readingEnd)
        guard japaneseRubyKanaComparisonKey(String(surface[previousSurfaceIndex]))
            == japaneseRubyKanaComparisonKey(String(normalizedReading[previousReadingIndex])) else {
            break
        }
        surfaceEnd = previousSurfaceIndex
        readingEnd = previousReadingIndex
    }

    let rubySurface = String(surface[surfaceStart..<surfaceEnd])
    let rubyReading = String(normalizedReading[readingStart..<readingEnd])
    guard rubySurface.hasKanji, !rubyReading.isEmpty else { return nil }

    return JapaneseRubyAnnotationAlignment(
        surfacePrefix: String(surface[..<surfaceStart]),
        rubySurface: rubySurface,
        rubyReading: rubyReading,
        surfaceSuffix: String(surface[surfaceEnd...])
    )
}

public func makeJapaneseRubyMarkup(
    surface: String,
    reading: String,
    normalizeReadingToHiragana: Bool = true
) -> String {
    guard let alignment = alignJapaneseRubyAnnotation(
        surface: surface, reading: reading, normalizeReadingToHiragana: normalizeReadingToHiragana
    ) else {
        guard surface.hasKanji, !reading.isEmpty else { return surface }
        let normalizedReading = normalizeReadingToHiragana ? reading.withKatakanaToHiragana : reading
        // Trimming must not erase a reading when the remaining kanji cannot be
        // aligned. Keep the supplied reading over the full written form.
        return surface == normalizedReading ? surface : "｜\(surface)《\(normalizedReading)》"
    }
    return alignment.surfacePrefix
        + (splitJapaneseRubyMarkup(surface: alignment.rubySurface, reading: alignment.rubyReading)
            ?? "｜\(alignment.rubySurface)《\(alignment.rubyReading)》")
        + alignment.surfaceSuffix
}

// Kana between kanji runs anchors the reading only when exactly one partition
// consumes it in full. Ambiguous readings retain the existing grouped ruby.
private func splitJapaneseRubyMarkup(surface: String, reading: String) -> String? {
    let surfaceCharacters = Array(surface)
    var runs: [String] = []
    var start = 0
    for index in surfaceCharacters.indices.dropFirst() {
        if isJapaneseRubyKana(String(surfaceCharacters[index])) != isJapaneseRubyKana(String(surfaceCharacters[start])) {
            runs.append(String(surfaceCharacters[start..<index]))
            start = index
        }
    }
    runs.append(String(surfaceCharacters[start...]))
    guard runs.contains(where: isJapaneseRubyKana),
          runs.allSatisfy({ isJapaneseRubyKana($0) || $0.hasKanji }) else { return nil }
    let readingCharacters = Array(reading)
    let matchingReadingCharacters = Array(japaneseRubyKanaComparisonKey(reading))
    guard matchingReadingCharacters.count == readingCharacters.count else { return nil }
    let anchors: [[Character]?] = runs.map { isJapaneseRubyKana($0) ? Array(japaneseRubyKanaComparisonKey($0)) : nil }

    // The earliest and latest valid placements coincide exactly when there is
    // one partition. A kanji run consumes at least one reading character;
    // choosing an earlier anchor can only leave more space for later anchors.
    // Scan in both directions rather than recursively retaining partial markup.
    func partition(anchors: [[Character]?], reading: [Character]) -> [Range<Int>]? {
        var ranges: [Range<Int>] = []
        var cursor = 0
        for (index, anchor) in anchors.enumerated() {
            guard let anchor else {
                guard cursor < reading.count else { return nil }
                ranges.append(cursor..<(cursor + 1))
                cursor += 1
                continue
            }

            let position: Int
            if index == 0 {
                position = 0
            } else if index == anchors.count - 1 {
                position = reading.count - anchor.count
            } else {
                guard let match = firstKanaAnchor(anchor, in: reading, startingAt: cursor) else { return nil }
                position = match
            }
            guard position >= cursor, position <= reading.count - anchor.count,
                  reading[position..<(position + anchor.count)].elementsEqual(anchor) else { return nil }
            if index > 0 {
                ranges[index - 1] = ranges[index - 1].lowerBound..<position
            }
            cursor = position + anchor.count
            ranges.append(position..<cursor)
        }
        if anchors.last! == nil {
            ranges[ranges.count - 1] = ranges.last!.lowerBound..<reading.count
        } else if cursor != reading.count {
            return nil
        }
        return ranges
    }

    guard let earliest = partition(anchors: anchors, reading: matchingReadingCharacters),
          let reversed = partition(
            anchors: anchors.reversed().map { $0.map { Array($0.reversed()) } },
            reading: Array(matchingReadingCharacters.reversed())
          ) else { return nil }
    let latest = reversed.reversed().map { (readingCharacters.count - $0.upperBound)..<(readingCharacters.count - $0.lowerBound) }
    guard earliest == latest else { return nil }
    return runs.indices.map { index in
        anchors[index] != nil ? runs[index] : "｜\(runs[index])《\(String(readingCharacters[earliest[index]]))》"
    }.joined()
}

// KMP keeps long, repeated kana prefixes from rescanning the same reading.
private func firstKanaAnchor(_ anchor: [Character], in reading: [Character], startingAt start: Int) -> Int? {
    guard !anchor.isEmpty, start <= reading.count - anchor.count else { return nil }
    var fallback = [Int](repeating: 0, count: anchor.count)
    var matched = 0
    for index in anchor.indices.dropFirst() {
        while matched > 0, anchor[index] != anchor[matched] { matched = fallback[matched - 1] }
        if anchor[index] == anchor[matched] { matched += 1 }
        fallback[index] = matched
    }
    matched = 0
    for index in start..<reading.count {
        while matched > 0, reading[index] != anchor[matched] { matched = fallback[matched - 1] }
        if reading[index] == anchor[matched] { matched += 1 }
        if matched == anchor.count { return index + 1 - anchor.count }
    }
    return nil
}
