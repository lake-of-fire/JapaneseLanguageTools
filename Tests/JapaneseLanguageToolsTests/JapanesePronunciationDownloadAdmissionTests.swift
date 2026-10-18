import Foundation
import XCTest
@testable import JapaneseLanguageTools

final class JapanesePronunciationDownloadAdmissionTests: XCTestCase {
    private let url = URL(string: "https://manabi.io/media/audio/tofugu/pronunciation.mp3")!

    func test_onlyCompleteMP3ResponseFromOwnedOriginIsAdmitted() throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "audio/mpeg", "Content-Length": "123"]
        ))
        XCTAssertNoThrow(try JapanesePronunciationAudioDownloader.validate(response: response))
    }

    func test_untrustedOriginAndIncompleteResponseSemanticsAreRejected() throws {
        for address in [
            "http://manabi.io/media/audio/tofugu/pronunciation.mp3",
            "https://example.invalid/media/audio/tofugu/pronunciation.mp3",
            "https://user@manabi.io/media/audio/tofugu/pronunciation.mp3",
            "https://manabi.io:444/media/audio/tofugu/pronunciation.mp3",
            "https://manabi.io/elsewhere/pronunciation.mp3"
        ] {
            let untrusted = try XCTUnwrap(URL(string: address))
            XCTAssertFalse(JapanesePronunciationAudioDownloader.allows(url: untrusted))
            assertRejected(try XCTUnwrap(HTTPURLResponse(
                url: untrusted, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "audio/mpeg"]
            )))
        }
        for fields in [
            ["Content-Type": "text/html"],
            ["Content-Type": "audio/mpeg", "Content-Length": "0"],
            ["Content-Type": "audio/mpeg", "Content-Length": "-1"],
            ["Content-Type": "audio/mpeg", "Content-Length": "invalid"],
            ["Content-Type": "audio/mpeg", "Content-Length": "999999999999"],
            ["Content-Type": "audio/mpeg", "Content-Range": "bytes 0-10/100"],
            ["Content-Type": "audio/mpeg", "Content-Encoding": "gzip"]
        ] {
            assertRejected(try XCTUnwrap(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: fields
            )))
        }
    }

    func test_emptyHTMLMalformedAndOversizedFilesAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let candidates = [
            Data(), Data("<html>error</html>".utf8),
            Data([0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 0]),
            Data([0xff, 0xfb, 0, 0]),
            Data(repeating: 0, count: JapanesePronunciationAudioDownloader.maximumAudioBytes + 1)
        ]
        for (index, data) in candidates.enumerated() {
            let file = root.appendingPathComponent("\(index).mp3")
            try data.write(to: file)
            XCTAssertThrowsError(try JapanesePronunciationAudioDownloader.validateAudioFile(at: file))
        }
        XCTAssertThrowsError(try JapanesePronunciationAudioDownloader.validateAudioFile(at: root))
    }

    func test_redirectAndFailedHTTPResponses_areRejected() throws {
        for status in [199, 204, 206, 299, 300, 302, 404, 429, 500] {
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "audio/mpeg"]
            ))
            assertRejected(response)
        }
    }

    func test_nonHTTPResponse_isRejected() {
        assertRejected(URLResponse(url: url, mimeType: "audio/mpeg", expectedContentLength: 10, textEncodingName: nil))
    }

    private func assertRejected(_ response: URLResponse, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(
            try JapanesePronunciationAudioDownloader.validate(response: response), file: file, line: line
        ) { error in
            XCTAssertEqual((error as? URLError)?.code, .badServerResponse, file: file, line: line)
        }
    }
}
