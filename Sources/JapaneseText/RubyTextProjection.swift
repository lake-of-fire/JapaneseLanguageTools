public struct RubyTextProjection: Equatable, Sendable {
    public let surface: String
    public let reading: String
    public let containsRuby: Bool
}

/// One accepted annotation or an untouched literal gap, using the projection
/// parser's grammar. Joining `source` reproduces the original UTF-8 exactly.
public struct RubyTextComponent: Equatable, Sendable {
    public let source: String
    public let surface: String
    public let reading: String?
}

private struct RubyTextProjectionMatch {
    let endIndex: Int
    let surface: [UInt8]
    let reading: [UInt8]
}

private enum RubyTextHTMLTagName {
    case ruby
    case reading
    case readingParenthesis
    case other
}

private struct RubyTextHTMLTag {
    let endIndex: Int
    let name: RubyTextHTMLTagName
    let isClosing: Bool
    let isSelfClosing: Bool
}

private enum RubyTextProjectionUTF8 {
    static let annotationStartFirst: UInt8 = 0xEF // First byte of `｜`
    static let annotationStart: [UInt8] = [0xEF, 0xBD, 0x9C] // `｜`
    static let readingStart: [UInt8] = [0xE3, 0x80, 0x8A] // `《`
    static let readingEnd: [UInt8] = [0xE3, 0x80, 0x8B] // `》`

    static let lessThan = UInt8(ascii: "<")
    static let greaterThan = UInt8(ascii: ">")
    static let slash = UInt8(ascii: "/")
    static let singleQuote = UInt8(ascii: "'")
    static let doubleQuote = UInt8(ascii: "\"")
    static let hyphen = UInt8(ascii: "-")
    static let uppercaseA = UInt8(ascii: "A")
    static let uppercaseZ = UInt8(ascii: "Z")
    static let lowercaseA = UInt8(ascii: "a")
    static let lowercaseZ = UInt8(ascii: "z")
    static let zero = UInt8(ascii: "0")
    static let nine = UInt8(ascii: "9")
    static let asciiCaseOffset: UInt8 = 0x20

    static let horizontalTab: UInt8 = 0x09
    static let lineFeed: UInt8 = 0x0A
    static let formFeed: UInt8 = 0x0C
    static let carriageReturn: UInt8 = 0x0D
    static let space: UInt8 = 0x20

    static let ruby = Array("ruby".utf8)
    static let readingTag = Array("rt".utf8)
    static let readingParenthesisTag = Array("rp".utf8)
}

@inline(__always)
private func rubyTextBytesMatch(
    _ token: [UInt8],
    in bytes: UnsafeBufferPointer<UInt8>,
    at index: Int
) -> Bool {
    guard index >= 0, index <= bytes.count - token.count else { return false }
    for offset in token.indices where bytes[index + offset] != token[offset] {
        return false
    }
    return true
}

@inline(__always)
private func rubyTextIsASCIIWhitespace(_ byte: UInt8) -> Bool {
    byte == RubyTextProjectionUTF8.space
        || byte == RubyTextProjectionUTF8.horizontalTab
        || byte == RubyTextProjectionUTF8.lineFeed
        || byte == RubyTextProjectionUTF8.formFeed
        || byte == RubyTextProjectionUTF8.carriageReturn
}

@inline(__always)
private func rubyTextIsASCIITagNameByte(_ byte: UInt8) -> Bool {
    (byte >= RubyTextProjectionUTF8.uppercaseA && byte <= RubyTextProjectionUTF8.uppercaseZ)
        || (byte >= RubyTextProjectionUTF8.lowercaseA && byte <= RubyTextProjectionUTF8.lowercaseZ)
        || (byte >= RubyTextProjectionUTF8.zero && byte <= RubyTextProjectionUTF8.nine)
        || byte == RubyTextProjectionUTF8.hyphen
}

@inline(__always)
private func rubyTextIsHTMLTagNameDelimiter(_ byte: UInt8) -> Bool {
    rubyTextIsASCIIWhitespace(byte)
        || byte == RubyTextProjectionUTF8.slash
        || byte == RubyTextProjectionUTF8.greaterThan
}

@inline(__always)
private func rubyTextLowercasedASCII(_ byte: UInt8) -> UInt8 {
    guard byte >= RubyTextProjectionUTF8.uppercaseA,
          byte <= RubyTextProjectionUTF8.uppercaseZ else {
        return byte
    }
    return byte + RubyTextProjectionUTF8.asciiCaseOffset
}

private func rubyTextTagNameEquals(
    _ expected: [UInt8],
    in bytes: UnsafeBufferPointer<UInt8>,
    range: Range<Int>
) -> Bool {
    guard range.count == expected.count else { return false }
    for offset in expected.indices {
        if rubyTextLowercasedASCII(bytes[range.lowerBound + offset]) != expected[offset] {
            return false
        }
    }
    return true
}

private func rubyTextHTMLTag(
    in bytes: UnsafeBufferPointer<UInt8>,
    at startIndex: Int
) -> RubyTextHTMLTag? {
    guard startIndex < bytes.count,
          bytes[startIndex] == RubyTextProjectionUTF8.lessThan else {
        return nil
    }

    var index = startIndex + 1
    guard index < bytes.count else { return nil }

    let isClosing = bytes[index] == RubyTextProjectionUTF8.slash
    if isClosing {
        index += 1
    }

    let nameStart = index
    while index < bytes.count, rubyTextIsASCIITagNameByte(bytes[index]) {
        index += 1
    }
    guard index > nameStart else { return nil }
    guard index < bytes.count, rubyTextIsHTMLTagNameDelimiter(bytes[index]) else {
        return nil
    }
    let nameRange = nameStart..<index

    let name: RubyTextHTMLTagName
    if rubyTextTagNameEquals(RubyTextProjectionUTF8.ruby, in: bytes, range: nameRange) {
        name = .ruby
    } else if rubyTextTagNameEquals(RubyTextProjectionUTF8.readingTag, in: bytes, range: nameRange) {
        name = .reading
    } else if rubyTextTagNameEquals(
        RubyTextProjectionUTF8.readingParenthesisTag,
        in: bytes,
        range: nameRange
    ) {
        name = .readingParenthesis
    } else {
        name = .other
    }

    var quote: UInt8?
    while index < bytes.count {
        let byte = bytes[index]
        if let activeQuote = quote {
            if byte == activeQuote {
                quote = nil
            }
        } else if byte == RubyTextProjectionUTF8.singleQuote
            || byte == RubyTextProjectionUTF8.doubleQuote {
            quote = byte
        } else if byte == RubyTextProjectionUTF8.greaterThan {
            var previousIndex = index
            while previousIndex > nameRange.upperBound,
                  rubyTextIsASCIIWhitespace(bytes[previousIndex - 1]) {
                previousIndex -= 1
            }
            return RubyTextHTMLTag(
                endIndex: index + 1,
                name: name,
                isClosing: isClosing,
                isSelfClosing: previousIndex > nameRange.upperBound
                    && bytes[previousIndex - 1] == RubyTextProjectionUTF8.slash
            )
        }
        index += 1
    }
    return nil
}

private func aozoraRubyMatch(
    in bytes: UnsafeBufferPointer<UInt8>,
    at startIndex: Int
) -> RubyTextProjectionMatch? {
    guard rubyTextBytesMatch(
        RubyTextProjectionUTF8.annotationStart,
        in: bytes,
        at: startIndex
    ) else {
        return nil
    }

    let surfaceStart = startIndex + RubyTextProjectionUTF8.annotationStart.count
    // A second annotation invalidates this surface; do not search past it.
    var readingTagStart = surfaceStart
    while !rubyTextBytesMatch(RubyTextProjectionUTF8.readingStart, in: bytes, at: readingTagStart) {
        guard readingTagStart < bytes.count,
              !rubyTextBytesMatch(RubyTextProjectionUTF8.annotationStart, in: bytes, at: readingTagStart) else {
            return nil
        }
        readingTagStart += 1
    }
    guard readingTagStart > surfaceStart else { return nil }

    let readingStart = readingTagStart + RubyTextProjectionUTF8.readingStart.count
    // Reject nested delimiters during the same scan that finds the reading end.
    var readingEnd = readingStart
    while !rubyTextBytesMatch(RubyTextProjectionUTF8.readingEnd, in: bytes, at: readingEnd) {
        guard readingEnd < bytes.count,
              !rubyTextBytesMatch(RubyTextProjectionUTF8.readingStart, in: bytes, at: readingEnd),
              !rubyTextBytesMatch(RubyTextProjectionUTF8.annotationStart, in: bytes, at: readingEnd) else {
            return nil
        }
        readingEnd += 1
    }
    guard readingEnd > readingStart else { return nil }

    return RubyTextProjectionMatch(
        endIndex: readingEnd + RubyTextProjectionUTF8.readingEnd.count,
        surface: Array(bytes[surfaceStart..<readingTagStart]),
        reading: Array(bytes[readingStart..<readingEnd])
    )
}

private func htmlRubyMatch(
    in bytes: UnsafeBufferPointer<UInt8>,
    at startIndex: Int
) -> RubyTextProjectionMatch? {
    // An opening ruby name is necessary before any attribute scan. Keep the
    // nested-tag parser unchanged, and never skip rejected source bytes.
    guard startIndex >= 0, startIndex <= bytes.count - 6,
          bytes[startIndex] == RubyTextProjectionUTF8.lessThan,
          rubyTextLowercasedASCII(bytes[startIndex + 1]) == UInt8(ascii: "r"),
          rubyTextLowercasedASCII(bytes[startIndex + 2]) == UInt8(ascii: "u"),
          rubyTextLowercasedASCII(bytes[startIndex + 3]) == UInt8(ascii: "b"),
          rubyTextLowercasedASCII(bytes[startIndex + 4]) == UInt8(ascii: "y"),
          rubyTextIsHTMLTagNameDelimiter(bytes[startIndex + 5]) else { return nil }

    guard let openingTag = rubyTextHTMLTag(in: bytes, at: startIndex),
          openingTag.name == .ruby,
          !openingTag.isClosing,
          !openingTag.isSelfClosing else {
        return nil
    }

    var surface = [UInt8]()
    var reading = [UInt8]()
    var readingDepth = 0
    var readingParenthesisDepth = 0
    var foundReading = false
    var index = openingTag.endIndex

    while index < bytes.count {
        if bytes[index] == RubyTextProjectionUTF8.lessThan {
            guard let tag = rubyTextHTMLTag(in: bytes, at: index) else {
                return nil
            }
            switch tag.name {
            case .ruby:
                guard tag.isClosing,
                      readingDepth == 0,
                      readingParenthesisDepth == 0,
                      !surface.isEmpty,
                      foundReading,
                      !reading.isEmpty else {
                    return nil
                }
                return RubyTextProjectionMatch(
                    endIndex: tag.endIndex,
                    surface: surface,
                    reading: reading
                )
            case .reading:
                if tag.isClosing {
                    guard readingDepth > 0 else { return nil }
                    readingDepth -= 1
                } else if !tag.isSelfClosing {
                    readingDepth += 1
                    foundReading = true
                }
            case .readingParenthesis:
                if tag.isClosing {
                    guard readingParenthesisDepth > 0 else { return nil }
                    readingParenthesisDepth -= 1
                } else if !tag.isSelfClosing {
                    readingParenthesisDepth += 1
                }
            case .other:
                break
            }
            index = tag.endIndex
            continue
        }

        if readingParenthesisDepth == 0 {
            if readingDepth > 0 {
                reading.append(bytes[index])
            } else {
                surface.append(bytes[index])
            }
        }
        index += 1
    }
    return nil
}

private func rubyTextProjectionMatch(
    in bytes: UnsafeBufferPointer<UInt8>,
    at startIndex: Int
) -> RubyTextProjectionMatch? {
    if bytes[startIndex] == RubyTextProjectionUTF8.lessThan {
        return htmlRubyMatch(in: bytes, at: startIndex)
    }
    if bytes[startIndex] == RubyTextProjectionUTF8.annotationStartFirst {
        return aozoraRubyMatch(in: bytes, at: startIndex)
    }
    return nil
}

private func projectRubyText(
    _ original: String,
    bytes: UnsafeBufferPointer<UInt8>
) -> RubyTextProjection {
    var surfaceBytes: [UInt8]?
    var readingBytes: [UInt8]?
    var index = 0
    var pendingStart = 0

    while index < bytes.count {
        guard let match = rubyTextProjectionMatch(in: bytes, at: index) else {
            index += 1
            continue
        }

        if surfaceBytes == nil {
            var surfacePrefix = Array(bytes.prefix(index))
            surfacePrefix.reserveCapacity(bytes.count)
            surfaceBytes = surfacePrefix

            var readingPrefix = surfacePrefix
            readingPrefix.reserveCapacity(bytes.count)
            readingBytes = readingPrefix
        } else if pendingStart < index {
            // Preserve the untouched gap in one append per output, including
            // malformed candidates and unrelated markup traversed above.
            if index == pendingStart + 1 {
                surfaceBytes?.append(bytes[pendingStart])
                readingBytes?.append(bytes[pendingStart])
            } else {
                surfaceBytes?.append(contentsOf: bytes[pendingStart..<index])
                readingBytes?.append(contentsOf: bytes[pendingStart..<index])
            }
        }

        surfaceBytes?.append(contentsOf: match.surface)
        readingBytes?.append(contentsOf: match.reading)
        index = match.endIndex
        pendingStart = index
    }

    if surfaceBytes != nil, pendingStart < bytes.count {
        if pendingStart == bytes.count - 1 {
            surfaceBytes?.append(bytes[pendingStart])
            readingBytes?.append(bytes[pendingStart])
        } else {
            surfaceBytes?.append(contentsOf: bytes[pendingStart..<bytes.count])
            readingBytes?.append(contentsOf: bytes[pendingStart..<bytes.count])
        }
    }

    guard let surfaceBytes, let readingBytes else {
        return RubyTextProjection(
            surface: original,
            reading: original,
            containsRuby: false
        )
    }
    return RubyTextProjection(
        surface: String(decoding: surfaceBytes, as: UTF8.self),
        reading: String(decoding: readingBytes, as: UTF8.self),
        containsRuby: true
    )
}

public func projectRubyText(_ text: String) -> RubyTextProjection {
    if let projection = text.utf8.withContiguousStorageIfAvailable({ bytes in
        projectRubyText(text, bytes: bytes)
    }) {
        return projection
    }

    let bytes = Array(text.utf8)
    return bytes.withUnsafeBufferPointer {
        projectRubyText(text, bytes: $0)
    }
}

private func rubyTextComponents(
    _ text: String,
    bytes: UnsafeBufferPointer<UInt8>,
    includingHTML: Bool
) -> [RubyTextComponent] {
    var result: [RubyTextComponent] = []
    var index = 0
    var pendingStart = 0
    while index < bytes.count {
        if !includingHTML, bytes[index] == RubyTextProjectionUTF8.lessThan {
            index += 1
            continue
        }
        guard let match = rubyTextProjectionMatch(in: bytes, at: index) else {
            index += 1
            continue
        }
        if pendingStart < index {
            let literal = String(decoding: bytes[pendingStart..<index], as: UTF8.self)
            result.append(.init(source: literal, surface: literal, reading: nil))
        }
        result.append(.init(
            source: String(decoding: bytes[index..<match.endIndex], as: UTF8.self),
            surface: String(decoding: match.surface, as: UTF8.self),
            reading: String(decoding: match.reading, as: UTF8.self)
        ))
        index = match.endIndex
        pendingStart = index
    }
    if result.isEmpty {
        return text.isEmpty ? [] : [.init(source: text, surface: text, reading: nil)]
    }
    if pendingStart < bytes.count {
        let literal = String(decoding: bytes[pendingStart..<bytes.count], as: UTF8.self)
        result.append(.init(source: literal, surface: literal, reading: nil))
    }
    return result
}

/// Parses pipe and HTML ruby without interpreting rejected markup as ruby or
/// discarding punctuation, malformed prefixes, or other literal source text.
/// Set `includingHTML` to false for consumers that render HTML literally.
public func rubyTextComponents(in text: String, includingHTML: Bool = true) -> [RubyTextComponent] {
    if let components = text.utf8.withContiguousStorageIfAvailable({ bytes in
        rubyTextComponents(text, bytes: bytes, includingHTML: includingHTML)
    }) {
        return components
    }
    return Array(text.utf8).withUnsafeBufferPointer {
        rubyTextComponents(text, bytes: $0, includingHTML: includingHTML)
    }
}

public extension String {
    var removingRubyText: String {
        projectRubyText(self).surface
    }

    var replacingRubyText: String {
        projectRubyText(self).reading
    }
}
