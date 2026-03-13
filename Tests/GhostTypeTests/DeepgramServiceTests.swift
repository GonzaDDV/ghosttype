import XCTest
@testable import GhostType

final class DeepgramServiceTests: XCTestCase {
    func testParseTranscriptResponse() {
        let json = """
        {
            "type": "Results",
            "channel_index": [0, 1],
            "duration": 1.5,
            "start": 0.0,
            "is_final": true,
            "channel": {
                "alternatives": [
                    {
                        "transcript": "hello world",
                        "confidence": 0.98
                    }
                ]
            }
        }
        """
        let result = DeepgramService.parseTranscript(from: json.data(using: .utf8)!)
        XCTAssertEqual(result?.transcript, "hello world")
        XCTAssertTrue(result?.isFinal ?? false)
    }

    func testParseEmptyTranscript() {
        let json = """
        {
            "type": "Results",
            "channel_index": [0, 1],
            "duration": 0.5,
            "start": 0.0,
            "is_final": false,
            "channel": {
                "alternatives": [
                    {
                        "transcript": "",
                        "confidence": 0.0
                    }
                ]
            }
        }
        """
        let result = DeepgramService.parseTranscript(from: json.data(using: .utf8)!)
        XCTAssertEqual(result?.transcript, "")
        XCTAssertFalse(result?.isFinal ?? true)
    }

    func testParseInvalidJSON() {
        let data = "not json".data(using: .utf8)!
        let result = DeepgramService.parseTranscript(from: data)
        XCTAssertNil(result)
    }

    func testBuildWebSocketURL() {
        let url = DeepgramService.buildWebSocketURL(apiKey: "test-key")
        XCTAssertEqual(url.scheme, "wss")
        XCTAssertEqual(url.host, "api.deepgram.com")
        XCTAssertTrue(url.path.contains("/listen"))
        let query = url.query ?? ""
        XCTAssertTrue(query.contains("encoding=linear16"))
        XCTAssertTrue(query.contains("sample_rate=16000"))
        XCTAssertTrue(query.contains("channels=1"))
        XCTAssertTrue(query.contains("punctuate=true"))
    }
}
