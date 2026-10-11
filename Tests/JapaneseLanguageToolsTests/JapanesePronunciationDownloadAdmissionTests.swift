import Foundation
import XCTest
@testable import JapaneseLanguageTools

final class JapanesePronunciationDownloadAdmissionTests: XCTestCase {
    private let url = URL(string: "https://manabi.io/media/audio/tofugu/pronunciation.mp3")!

    func test_successfulHTTPResponses_areAdmitted() throws {
        for status in [200, 206, 299] {
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
            ))
            XCTAssertNoThrow(try JapanesePronunciationAudioDownloader.validate(response: response))
        }
    }

    func test_redirectAndFailedHTTPResponses_areRejected() throws {
        for status in [199, 300, 302, 404, 429, 500] {
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
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
