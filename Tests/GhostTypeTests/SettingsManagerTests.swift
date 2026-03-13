import XCTest
@testable import GhostType

final class SettingsManagerTests: XCTestCase {
    private var settings: SettingsManager!
    private let testSuite = "com.ghosttype.test.settings"

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: testSuite)!
        defaults.removePersistentDomain(forName: testSuite)
        settings = SettingsManager(defaults: defaults, keychainService: "com.ghosttype.test.keys")
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removePersistentDomain(forName: testSuite)
        KeychainHelper.delete(service: "com.ghosttype.test.keys", account: "deepgram")
        KeychainHelper.delete(service: "com.ghosttype.test.keys", account: "openrouter")
    }

    func testDefaultDictationModeIsToggle() {
        XCTAssertEqual(settings.dictationMode, .toggle)
    }

    func testSetDictationMode() {
        settings.dictationMode = .holdToTalk
        XCTAssertEqual(settings.dictationMode, .holdToTalk)
    }

    func testDefaultInsertionMethodIsClipboard() {
        XCTAssertEqual(settings.insertionMethod, .clipboard)
    }

    func testDefaultLLMModel() {
        XCTAssertEqual(settings.llmModel, "google/gemini-2.0-flash-exp")
    }

    func testSetLLMModel() {
        settings.llmModel = "meta-llama/llama-3.1-8b-instruct"
        XCTAssertEqual(settings.llmModel, "meta-llama/llama-3.1-8b-instruct")
    }

    func testDefaultHistoryPath() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ghosttype/history").path
        XCTAssertEqual(settings.historyPath, expected)
    }

    func testDeepgramApiKey() {
        settings.deepgramApiKey = "dg-key-123"
        XCTAssertEqual(settings.deepgramApiKey, "dg-key-123")
    }

    func testOpenRouterApiKey() {
        settings.openRouterApiKey = "or-key-456"
        XCTAssertEqual(settings.openRouterApiKey, "or-key-456")
    }

    func testHasRequiredApiKeys() {
        XCTAssertFalse(settings.hasRequiredApiKeys)
        settings.deepgramApiKey = "key1"
        XCTAssertFalse(settings.hasRequiredApiKeys)
        settings.openRouterApiKey = "key2"
        XCTAssertTrue(settings.hasRequiredApiKeys)
    }

    func testDefaultLaunchAtLogin() {
        XCTAssertFalse(settings.launchAtLogin)
    }
}
