import XCTest
@testable import GhostType

final class LLMCleanupServiceTests: XCTestCase {
    func testBuildRequestBody() throws {
        let body = LLMCleanupService.buildRequestBody(
            transcript: "um so like hello world",
            model: "google/gemini-2.0-flash-exp"
        )

        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        XCTAssertEqual(json["model"] as? String, "google/gemini-2.0-flash-exp")

        let messages = json["messages"] as! [[String: String]]
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertTrue(messages[0]["content"]!.contains("filler words"))
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(messages[1]["content"], "um so like hello world")
    }

    func testBuildRequest() {
        let request = LLMCleanupService.buildRequest(apiKey: "test-key")
        XCTAssertEqual(request.url?.host, "openrouter.ai")
        XCTAssertEqual(request.url?.path, "/api/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testParseResponseBody() {
        let json = """
        {
            "choices": [
                {
                    "message": {
                        "content": "Hello world"
                    }
                }
            ]
        }
        """
        let result = LLMCleanupService.parseResponse(from: json.data(using: .utf8)!)
        XCTAssertEqual(result, "Hello world")
    }

    func testParseInvalidResponse() {
        let result = LLMCleanupService.parseResponse(from: "bad".data(using: .utf8)!)
        XCTAssertNil(result)
    }

    func testParseEmptyChoices() {
        let json = """
        {"choices": []}
        """
        let result = LLMCleanupService.parseResponse(from: json.data(using: .utf8)!)
        XCTAssertNil(result)
    }
}
