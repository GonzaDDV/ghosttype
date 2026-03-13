# GhostType Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app that captures speech, transcribes via Deepgram, cleans up via OpenRouter, and inserts text at the cursor.

**Architecture:** Standalone Swift macOS app using AppKit for the menu bar UI. AVAudioEngine captures mic audio, streams raw PCM to Deepgram via WebSocket, sends final transcript to OpenRouter for cleanup, then inserts via clipboard paste. All processing is cloud-based — zero local CPU impact.

**Tech Stack:** Swift, AppKit, AVAudioEngine, URLSessionWebSocketTask, URLSession, CGEvent, NSPasteboard, Keychain, UserDefaults

---

## File Structure

```
GhostType/
├── Package.swift                          # SPM manifest
├── Sources/
│   └── GhostType/
│       ├── main.swift                     # Entry point, NSApplication setup
│       ├── AppDelegate.swift              # App lifecycle, wires components together
│       ├── AppState.swift                 # State machine: Idle → Recording → Processing → Inserting
│       ├── Audio/
│       │   └── AudioCaptureManager.swift  # AVAudioEngine mic capture, PCM chunks via callback
│       ├── Services/
│       │   ├── DeepgramService.swift      # WebSocket streaming to Deepgram, transcript callback
│       │   ├── LLMCleanupService.swift    # OpenRouter HTTP API for text cleanup
│       │   └── TextInsertionService.swift # Clipboard paste + CGEvent Cmd+V, AX fallback
│       ├── Input/
│       │   └── HotkeyManager.swift        # CGEvent tap for global hotkey, toggle/hold modes
│       ├── Storage/
│       │   ├── TranscriptionLogger.swift  # Daily .jsonl file logging
│       │   ├── KeychainHelper.swift       # Keychain read/write for API keys
│       │   └── SettingsManager.swift      # UserDefaults wrapper for all settings
│       └── UI/
│           ├── MenuBarController.swift    # NSStatusItem, state-aware icon, dropdown menu
│           └── SettingsWindowController.swift # NSWindow for settings form
└── Tests/
    └── GhostTypeTests/
        ├── AppStateTests.swift
        ├── DeepgramServiceTests.swift
        ├── LLMCleanupServiceTests.swift
        ├── TextInsertionServiceTests.swift
        ├── TranscriptionLoggerTests.swift
        ├── KeychainHelperTests.swift
        └── SettingsManagerTests.swift
```

---

## Chunk 1: Project Scaffold + Core State Machine

### Task 1: Initialize Swift Package

**Files:**
- Create: `Package.swift`
- Create: `Sources/GhostType/main.swift`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GhostType",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "GhostType",
            path: "Sources/GhostType"
        ),
        .testTarget(
            name: "GhostTypeTests",
            dependencies: ["GhostType"],
            path: "Tests/GhostTypeTests"
        )
    ]
)
```

- [ ] **Step 2: Create minimal main.swift**

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // Menu bar only, no dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 3: Create stub AppDelegate.swift**

```swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("GhostType launched")
    }
}
```

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: Build succeeds, no errors

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/
git commit -m "feat: initialize Swift package with menu bar app entry point"
```

### Task 2: AppState State Machine

**Files:**
- Create: `Sources/GhostType/AppState.swift`
- Create: `Tests/GhostTypeTests/AppStateTests.swift`

- [ ] **Step 1: Write failing tests for AppState**

```swift
import XCTest
@testable import GhostType

final class AppStateTests: XCTestCase {
    func testInitialStateIsIdle() {
        let state = AppState()
        XCTAssertEqual(state.current, .idle)
    }

    func testTransitionFromIdleToRecording() {
        let state = AppState()
        XCTAssertTrue(state.transition(to: .recording))
        XCTAssertEqual(state.current, .recording)
    }

    func testTransitionFromRecordingToProcessing() {
        let state = AppState()
        state.transition(to: .recording)
        XCTAssertTrue(state.transition(to: .processing))
        XCTAssertEqual(state.current, .processing)
    }

    func testTransitionFromProcessingToInserting() {
        let state = AppState()
        state.transition(to: .recording)
        state.transition(to: .processing)
        XCTAssertTrue(state.transition(to: .inserting))
        XCTAssertEqual(state.current, .inserting)
    }

    func testTransitionFromInsertingToIdle() {
        let state = AppState()
        state.transition(to: .recording)
        state.transition(to: .processing)
        state.transition(to: .inserting)
        XCTAssertTrue(state.transition(to: .idle))
        XCTAssertEqual(state.current, .idle)
    }

    func testInvalidTransitionFromIdleToProcessing() {
        let state = AppState()
        XCTAssertFalse(state.transition(to: .processing))
        XCTAssertEqual(state.current, .idle)
    }

    func testInvalidTransitionFromIdleToInserting() {
        let state = AppState()
        XCTAssertFalse(state.transition(to: .inserting))
        XCTAssertEqual(state.current, .idle)
    }

    func testTransitionFromRecordingToIdleCancels() {
        let state = AppState()
        state.transition(to: .recording)
        XCTAssertTrue(state.transition(to: .idle))
        XCTAssertEqual(state.current, .idle)
    }

    func testOnChangeCallbackFires() {
        let state = AppState()
        var received: AppState.State?
        state.onChange = { newState in received = newState }
        state.transition(to: .recording)
        XCTAssertEqual(received, .recording)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AppStateTests`
Expected: FAIL — AppState not defined

- [ ] **Step 3: Implement AppState**

```swift
import Foundation

class AppState {
    enum State: Equatable {
        case idle
        case recording
        case processing
        case inserting
    }

    private(set) var current: State = .idle
    var onChange: ((State) -> Void)?

    private let validTransitions: [State: Set<State>] = [
        .idle: [.recording],
        .recording: [.processing, .idle],
        .processing: [.inserting, .idle],
        .inserting: [.idle]
    ]

    @discardableResult
    func transition(to newState: State) -> Bool {
        guard let allowed = validTransitions[current], allowed.contains(newState) else {
            return false
        }
        current = newState
        onChange?(newState)
        return true
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AppStateTests`
Expected: All 9 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostType/AppState.swift Tests/GhostTypeTests/AppStateTests.swift
git commit -m "feat: add AppState state machine with valid transition enforcement"
```

---

## Chunk 2: Storage Layer (Settings, Keychain, Logger)

### Task 3: KeychainHelper

**Files:**
- Create: `Sources/GhostType/Storage/KeychainHelper.swift`
- Create: `Tests/GhostTypeTests/KeychainHelperTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import GhostType

final class KeychainHelperTests: XCTestCase {
    private let testService = "com.ghosttype.test"

    override func tearDown() {
        super.tearDown()
        KeychainHelper.delete(service: testService, account: "testKey")
    }

    func testSaveAndRetrieve() {
        let saved = KeychainHelper.save(service: testService, account: "testKey", data: "secret123")
        XCTAssertTrue(saved)
        let retrieved = KeychainHelper.retrieve(service: testService, account: "testKey")
        XCTAssertEqual(retrieved, "secret123")
    }

    func testRetrieveNonExistent() {
        let retrieved = KeychainHelper.retrieve(service: testService, account: "noSuchKey")
        XCTAssertNil(retrieved)
    }

    func testUpdateExistingKey() {
        KeychainHelper.save(service: testService, account: "testKey", data: "old")
        KeychainHelper.save(service: testService, account: "testKey", data: "new")
        let retrieved = KeychainHelper.retrieve(service: testService, account: "testKey")
        XCTAssertEqual(retrieved, "new")
    }

    func testDelete() {
        KeychainHelper.save(service: testService, account: "testKey", data: "val")
        let deleted = KeychainHelper.delete(service: testService, account: "testKey")
        XCTAssertTrue(deleted)
        XCTAssertNil(KeychainHelper.retrieve(service: testService, account: "testKey"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter KeychainHelperTests`
Expected: FAIL — KeychainHelper not defined

- [ ] **Step 3: Implement KeychainHelper**

```swift
import Foundation
import Security

enum KeychainHelper {
    @discardableResult
    static func save(service: String, account: String, data: String) -> Bool {
        guard let data = data.data(using: .utf8) else { return false }

        // Delete existing item first
        delete(service: service, account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func retrieve(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter KeychainHelperTests`
Expected: All 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostType/Storage/KeychainHelper.swift Tests/GhostTypeTests/KeychainHelperTests.swift
git commit -m "feat: add KeychainHelper for secure API key storage"
```

### Task 4: SettingsManager

**Files:**
- Create: `Sources/GhostType/Storage/SettingsManager.swift`
- Create: `Tests/GhostTypeTests/SettingsManagerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SettingsManagerTests`
Expected: FAIL — SettingsManager not defined

- [ ] **Step 3: Implement SettingsManager**

```swift
import Foundation

class SettingsManager {
    enum DictationMode: String {
        case toggle
        case holdToTalk
    }

    enum InsertionMethod: String {
        case clipboard
        case accessibility
    }

    private let defaults: UserDefaults
    private let keychainService: String

    init(defaults: UserDefaults = .standard, keychainService: String = "com.ghosttype.keys") {
        self.defaults = defaults
        self.keychainService = keychainService
    }

    var dictationMode: DictationMode {
        get {
            guard let raw = defaults.string(forKey: "dictationMode"),
                  let mode = DictationMode(rawValue: raw) else { return .toggle }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: "dictationMode") }
    }

    var insertionMethod: InsertionMethod {
        get {
            guard let raw = defaults.string(forKey: "insertionMethod"),
                  let method = InsertionMethod(rawValue: raw) else { return .clipboard }
            return method
        }
        set { defaults.set(newValue.rawValue, forKey: "insertionMethod") }
    }

    var llmModel: String {
        get { defaults.string(forKey: "llmModel") ?? "google/gemini-2.0-flash-exp" }
        set { defaults.set(newValue, forKey: "llmModel") }
    }

    var historyPath: String {
        get {
            let defaultPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ghosttype/history").path
            return defaults.string(forKey: "historyPath") ?? defaultPath
        }
        set { defaults.set(newValue, forKey: "historyPath") }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }

    var deepgramApiKey: String? {
        get { KeychainHelper.retrieve(service: keychainService, account: "deepgram") }
        set {
            if let value = newValue {
                KeychainHelper.save(service: keychainService, account: "deepgram", data: value)
            } else {
                KeychainHelper.delete(service: keychainService, account: "deepgram")
            }
        }
    }

    var openRouterApiKey: String? {
        get { KeychainHelper.retrieve(service: keychainService, account: "openrouter") }
        set {
            if let value = newValue {
                KeychainHelper.save(service: keychainService, account: "openrouter", data: value)
            } else {
                KeychainHelper.delete(service: keychainService, account: "openrouter")
            }
        }
    }

    var hasRequiredApiKeys: Bool {
        deepgramApiKey != nil && openRouterApiKey != nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SettingsManagerTests`
Expected: All 10 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostType/Storage/SettingsManager.swift Tests/GhostTypeTests/SettingsManagerTests.swift
git commit -m "feat: add SettingsManager with UserDefaults and Keychain-backed properties"
```

### Task 5: TranscriptionLogger

**Files:**
- Create: `Sources/GhostType/Storage/TranscriptionLogger.swift`
- Create: `Tests/GhostTypeTests/TranscriptionLoggerTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import GhostType

final class TranscriptionLoggerTests: XCTestCase {
    private var logger: TranscriptionLogger!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghosttype-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        logger = TranscriptionLogger(historyDirectory: tempDir.path)
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testLogCreatesFile() throws {
        let entry = TranscriptionEntry(
            timestamp: Date(),
            rawTranscript: "um hello world",
            cleanedText: "Hello world",
            focusedApp: "com.apple.Terminal",
            model: "google/gemini-2.0-flash-exp",
            durationMs: 1500
        )
        try logger.log(entry)

        let dateStr = TranscriptionLogger.dateFormatter.string(from: entry.timestamp)
        let filePath = tempDir.appendingPathComponent("\(dateStr).jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath.path))
    }

    func testLogAppendsToExistingFile() throws {
        let entry1 = TranscriptionEntry(
            timestamp: Date(),
            rawTranscript: "first",
            cleanedText: "First",
            focusedApp: "com.apple.Terminal",
            model: "test-model",
            durationMs: 100
        )
        let entry2 = TranscriptionEntry(
            timestamp: Date(),
            rawTranscript: "second",
            cleanedText: "Second",
            focusedApp: "com.apple.Safari",
            model: "test-model",
            durationMs: 200
        )
        try logger.log(entry1)
        try logger.log(entry2)

        let dateStr = TranscriptionLogger.dateFormatter.string(from: Date())
        let filePath = tempDir.appendingPathComponent("\(dateStr).jsonl")
        let content = try String(contentsOf: filePath, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2)
    }

    func testRecentEntriesReturnsLatest() throws {
        for i in 0..<5 {
            let entry = TranscriptionEntry(
                timestamp: Date(),
                rawTranscript: "raw \(i)",
                cleanedText: "clean \(i)",
                focusedApp: "com.test",
                model: "m",
                durationMs: 100
            )
            try logger.log(entry)
        }
        let recent = try logger.recentEntries(count: 3)
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent.first?.cleanedText, "clean 4") // Most recent first
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TranscriptionLoggerTests`
Expected: FAIL — TranscriptionLogger not defined

- [ ] **Step 3: Implement TranscriptionLogger**

```swift
import Foundation

struct TranscriptionEntry: Codable {
    let timestamp: Date
    let rawTranscript: String
    let cleanedText: String
    let focusedApp: String
    let model: String
    let durationMs: Int

    enum CodingKeys: String, CodingKey {
        case timestamp
        case rawTranscript = "raw_transcript"
        case cleanedText = "cleaned_text"
        case focusedApp = "focused_app"
        case model
        case durationMs = "duration_ms"
    }
}

class TranscriptionLogger {
    let historyDirectory: String

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(historyDirectory: String) {
        self.historyDirectory = historyDirectory
    }

    func log(_ entry: TranscriptionEntry) throws {
        let dir = URL(fileURLWithPath: historyDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dateStr = Self.dateFormatter.string(from: entry.timestamp)
        let filePath = dir.appendingPathComponent("\(dateStr).jsonl")

        let jsonData = try encoder.encode(entry)
        guard var jsonString = String(data: jsonData, encoding: .utf8) else { return }
        jsonString += "\n"

        if FileManager.default.fileExists(atPath: filePath.path) {
            let handle = try FileHandle(forWritingTo: filePath)
            handle.seekToEndOfFile()
            handle.write(jsonString.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try jsonString.write(to: filePath, atomically: true, encoding: .utf8)
        }
    }

    func recentEntries(count: Int) throws -> [TranscriptionEntry] {
        let dir = URL(fileURLWithPath: historyDirectory)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // Newest date first

        var entries: [TranscriptionEntry] = []
        for file in files {
            guard entries.count < count else { break }
            let content = try String(contentsOf: file, encoding: .utf8)
            let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }.reversed()
            for line in lines {
                guard entries.count < count else { break }
                if let data = line.data(using: .utf8),
                   let entry = try? decoder.decode(TranscriptionEntry.self, from: data) {
                    entries.append(entry)
                }
            }
        }
        return entries
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TranscriptionLoggerTests`
Expected: All 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostType/Storage/TranscriptionLogger.swift Tests/GhostTypeTests/TranscriptionLoggerTests.swift
git commit -m "feat: add TranscriptionLogger with daily JSONL file storage"
```

---

## Chunk 3: Cloud Services (Deepgram + OpenRouter)

### Task 6: DeepgramService

**Files:**
- Create: `Sources/GhostType/Services/DeepgramService.swift`
- Create: `Tests/GhostTypeTests/DeepgramServiceTests.swift`

- [ ] **Step 1: Write failing tests**

Tests use a mock WebSocket approach — we test the message parsing and state management, not the actual network connection.

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DeepgramServiceTests`
Expected: FAIL — DeepgramService not defined

- [ ] **Step 3: Implement DeepgramService**

```swift
import Foundation

struct DeepgramTranscriptResult {
    let transcript: String
    let isFinal: Bool
    let confidence: Double
}

class DeepgramService {
    private var webSocketTask: URLSessionWebSocketTask?
    private let apiKey: String
    var onTranscript: ((DeepgramTranscriptResult) -> Void)?
    var onError: ((Error) -> Void)?

    private var finalTranscriptParts: [String] = []

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    static func buildWebSocketURL(apiKey: String) -> URL {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "api.deepgram.com"
        components.path = "/v1/listen"
        components.queryItems = [
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "interim_results", value: "false"),
            URLQueryItem(name: "model", value: "nova-2")
        ]
        return components.url!
    }

    func startStreaming() {
        finalTranscriptParts = []
        let url = Self.buildWebSocketURL(apiKey: apiKey)
        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        receiveMessage()
    }

    func sendAudio(_ data: Data) {
        webSocketTask?.send(.data(data)) { [weak self] error in
            if let error = error {
                self?.onError?(error)
            }
        }
    }

    func stopStreaming(completion: @escaping (String) -> Void) {
        // Send close message to signal end of audio
        let closeMessage = "{\"type\": \"CloseStream\"}"
        webSocketTask?.send(.string(closeMessage)) { [weak self] _ in
            // Give Deepgram a moment to send final results, then return accumulated transcript
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let fullTranscript = self?.finalTranscriptParts.joined(separator: " ") ?? ""
                completion(fullTranscript)
                self?.webSocketTask?.cancel(with: .normalClosure, reason: nil)
                self?.webSocketTask = nil
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let parsed = Self.parseTranscript(from: data) {
                        if parsed.isFinal && !parsed.transcript.isEmpty {
                            self?.finalTranscriptParts.append(parsed.transcript)
                        }
                        self?.onTranscript?(parsed)
                    }
                default:
                    break
                }
                self?.receiveMessage() // Continue listening
            case .failure(let error):
                self?.onError?(error)
            }
        }
    }

    static func parseTranscript(from data: Data) -> DeepgramTranscriptResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let first = alternatives.first,
              let transcript = first["transcript"] as? String else {
            return nil
        }

        let isFinal = json["is_final"] as? Bool ?? false
        let confidence = first["confidence"] as? Double ?? 0.0

        return DeepgramTranscriptResult(
            transcript: transcript,
            isFinal: isFinal,
            confidence: confidence
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DeepgramServiceTests`
Expected: All 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostType/Services/DeepgramService.swift Tests/GhostTypeTests/DeepgramServiceTests.swift
git commit -m "feat: add DeepgramService with WebSocket streaming and transcript parsing"
```

### Task 7: LLMCleanupService

**Files:**
- Create: `Sources/GhostType/Services/LLMCleanupService.swift`
- Create: `Tests/GhostTypeTests/LLMCleanupServiceTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LLMCleanupServiceTests`
Expected: FAIL — LLMCleanupService not defined

- [ ] **Step 3: Implement LLMCleanupService**

```swift
import Foundation

class LLMCleanupService {
    private let apiKey: String
    private let model: String

    static let systemPrompt = """
    Clean up this dictated text. Remove filler words (um, uh, like, you know), \
    fix punctuation and capitalization. Return only the cleaned text. \
    Do not change the meaning or add anything.
    """

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    func cleanup(_ transcript: String, completion: @escaping (Result<String, Error>) -> Void) {
        var request = Self.buildRequest(apiKey: apiKey)
        request.httpBody = Self.buildRequestBody(transcript: transcript, model: model)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data, let cleaned = Self.parseResponse(from: data) else {
                completion(.failure(LLMError.invalidResponse))
                return
            }
            completion(.success(cleaned))
        }.resume()
    }

    static func buildRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    static func buildRequestBody(transcript: String, model: String) -> Data {
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": transcript]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    static func parseResponse(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return nil
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum LLMError: Error {
        case invalidResponse
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LLMCleanupServiceTests`
Expected: All 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostType/Services/LLMCleanupService.swift Tests/GhostTypeTests/LLMCleanupServiceTests.swift
git commit -m "feat: add LLMCleanupService for OpenRouter text cleanup"
```

---

## Chunk 4: System Integration (Audio, Hotkeys, Text Insertion)

### Task 8: AudioCaptureManager

**Files:**
- Create: `Sources/GhostType/Audio/AudioCaptureManager.swift`

Note: AudioCaptureManager wraps AVAudioEngine which requires a real audio device — not unit-testable in CI. Integration tested manually and via the full pipeline.

- [ ] **Step 1: Implement AudioCaptureManager**

```swift
import AVFoundation

class AudioCaptureManager {
    private let engine = AVAudioEngine()
    var onAudioData: ((Data) -> Void)?
    var onError: ((Error) -> Void)?

    private(set) var isCapturing = false

    func startCapturing() throws {
        guard !isCapturing else { return }

        let inputNode = engine.inputNode
        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!

        // Install tap to get audio buffers
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: recordingFormat
        ) { [weak self] buffer, _ in
            guard let channelData = buffer.int16ChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let data = Data(bytes: channelData[0], count: frameLength * 2) // 2 bytes per Int16
            self?.onAudioData?(data)
        }

        engine.prepare()
        try engine.start()
        isCapturing = true
    }

    func stopCapturing() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/GhostType/Audio/AudioCaptureManager.swift
git commit -m "feat: add AudioCaptureManager for mic capture via AVAudioEngine"
```

### Task 9: TextInsertionService

**Files:**
- Create: `Sources/GhostType/Services/TextInsertionService.swift`
- Create: `Tests/GhostTypeTests/TextInsertionServiceTests.swift`

- [ ] **Step 1: Write failing tests**

Only the clipboard logic can be unit tested. CGEvent paste simulation and AX insertion require a running app context.

```swift
import XCTest
@testable import GhostType

final class TextInsertionServiceTests: XCTestCase {
    func testPrepareClipboardSetsText() {
        let service = TextInsertionService()
        let originalContent = NSPasteboard.general.string(forType: .string)

        service.prepareClipboard(with: "test text")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "test text")

        // Restore original
        if let original = originalContent {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(original, forType: .string)
        }
    }

    func testGetFocusedAppBundleId() {
        // Should return something when tests are running (Xcode or terminal)
        let bundleId = TextInsertionService.focusedAppBundleId()
        XCTAssertNotNil(bundleId)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TextInsertionServiceTests`
Expected: FAIL — TextInsertionService not defined

- [ ] **Step 3: Implement TextInsertionService**

```swift
import AppKit
import Carbon.HIToolbox

class TextInsertionService {
    private var savedClipboardContents: [NSPasteboardItem]?

    func insertText(_ text: String, method: SettingsManager.InsertionMethod = .clipboard) {
        switch method {
        case .clipboard:
            insertViaClipboard(text)
        case .accessibility:
            if !insertViaAccessibility(text) {
                insertViaClipboard(text) // Fallback
            }
        }
    }

    // MARK: - Clipboard Paste

    func prepareClipboard(with text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func insertViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Save all current clipboard items (not just plain text)
        let savedItems: [(NSPasteboard.PasteboardType, Data)] = pasteboard.pasteboardItems?.flatMap { item in
            item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        } ?? []

        // Set new text
        prepareClipboard(with: text)

        // Simulate Cmd+V
        simulatePaste()

        // Restore clipboard after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if !savedItems.isEmpty {
                let item = NSPasteboardItem()
                for (type, data) in savedItems {
                    item.setData(data, forType: type)
                }
                pasteboard.writeObjects([item])
            }
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Accessibility Insertion

    private func insertViaAccessibility(_ text: String) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success else { return false }

        let element = focusedElement as! AXUIElement

        // Try to insert at selected text range (non-destructive) first
        var rangeValue: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        if rangeResult == .success {
            // Replace selected text range with our text (inserts at cursor if no selection)
            let setResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
            if setResult == .success { return true }
        }

        // Fallback: set entire value (destructive — only if range insertion failed)
        let setResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        return setResult == .success
    }

    // MARK: - Utility

    static func focusedAppBundleId() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TextInsertionServiceTests`
Expected: All 2 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/GhostType/Services/TextInsertionService.swift Tests/GhostTypeTests/TextInsertionServiceTests.swift
git commit -m "feat: add TextInsertionService with clipboard paste and AX fallback"
```

### Task 10: HotkeyManager

**Files:**
- Create: `Sources/GhostType/Input/HotkeyManager.swift`

Note: CGEvent taps require Accessibility permission and a running event loop — not unit-testable. Tested manually.

- [ ] **Step 1: Implement HotkeyManager**

```swift
import Carbon.HIToolbox
import CoreGraphics

class HotkeyManager {
    enum Mode {
        case toggle
        case holdToTalk
    }

    var onRecordStart: (() -> Void)?
    var onRecordStop: (() -> Void)?

    var mode: Mode = .toggle
    var keyCode: CGKeyCode = CGKeyCode(kVK_Space)
    var modifierFlags: CGEventFlags = .maskAlternate // Option key

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRecording = false

    func start() -> Bool {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: hotkeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false // Accessibility permission not granted
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isRecording = false
    }

    fileprivate func handleKeyEvent(_ event: CGEvent, type: CGEventType) -> Bool {
        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let eventFlags = event.flags

        // Check if our modifier + key combo matches
        let modifierMatch = eventFlags.contains(modifierFlags)
        let keyMatch = eventKeyCode == keyCode

        guard modifierMatch && keyMatch else { return false }

        switch mode {
        case .toggle:
            if type == .keyDown {
                if isRecording {
                    isRecording = false
                    onRecordStop?()
                } else {
                    isRecording = true
                    onRecordStart?()
                }
                return true // Consume the event
            }
        case .holdToTalk:
            if type == .keyDown && !isRecording {
                isRecording = true
                onRecordStart?()
                return true
            } else if type == .keyUp && isRecording {
                isRecording = false
                onRecordStop?()
                return true
            }
        }

        return false
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passRetained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // Re-enable the tap if macOS disables it
        if let tap = manager.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    if manager.handleKeyEvent(event, type: type) {
        return nil // Consume the event
    }

    return Unmanaged.passRetained(event)
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/GhostType/Input/HotkeyManager.swift
git commit -m "feat: add HotkeyManager with CGEvent tap for global hotkeys"
```

---

## Chunk 5: UI + Wiring Everything Together

### Task 11: MenuBarController

**Files:**
- Create: `Sources/GhostType/UI/MenuBarController.swift`

- [ ] **Step 1: Implement MenuBarController**

```swift
import AppKit

class MenuBarController {
    private var statusItem: NSStatusItem!
    private let settings: SettingsManager
    private let logger: TranscriptionLogger
    var onSettingsClicked: (() -> Void)?

    init(settings: SettingsManager, logger: TranscriptionLogger) {
        self.settings = settings
        self.logger = logger
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(for: .idle)
        buildMenu()
    }

    func updateIcon(for state: AppState.State) {
        guard let button = statusItem.button else { return }
        switch state {
        case .idle:
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "GhostType")
        case .recording:
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
            button.contentTintColor = .systemRed
        case .processing:
            button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Processing")
            button.contentTintColor = .systemOrange
        case .inserting:
            button.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Done")
            button.contentTintColor = .systemGreen
        }

        if state == .idle {
            button.contentTintColor = nil
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        // Recent transcriptions submenu
        let recentItem = NSMenuItem(title: "Recent Transcriptions", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu()
        if let entries = try? logger.recentEntries(count: 10) {
            if entries.isEmpty {
                recentMenu.addItem(NSMenuItem(title: "No transcriptions yet", action: nil, keyEquivalent: ""))
            } else {
                for entry in entries {
                    let preview = String(entry.cleanedText.prefix(50))
                    let item = NSMenuItem(title: preview, action: #selector(copyTranscription(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = entry.cleanedText
                    recentMenu.addItem(item)
                }
            }
        }
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit GhostType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func refreshMenu() {
        buildMenu()
    }

    @objc private func copyTranscription(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func openSettings() {
        onSettingsClicked?()
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/GhostType/UI/MenuBarController.swift
git commit -m "feat: add MenuBarController with state-aware icons and recent transcriptions"
```

### Task 12: SettingsWindowController

**Files:**
- Create: `Sources/GhostType/UI/SettingsWindowController.swift`

- [ ] **Step 1: Implement SettingsWindowController**

```swift
import AppKit

class SettingsWindowController: NSWindowController {
    private let settings: SettingsManager
    private var deepgramField: NSSecureTextField!
    private var openRouterField: NSSecureTextField!
    private var modelField: NSTextField!
    private var modePopup: NSPopUpButton!
    private var insertionPopup: NSPopUpButton!
    private var historyPathField: NSTextField!
    private var launchAtLoginCheckbox: NSButton!

    var onSettingsSaved: (() -> Void)?

    init(settings: SettingsManager) {
        self.settings = settings

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "GhostType Settings"
        window.center()

        super.init(window: window)
        setupUI()
        loadValues()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20)
        ])

        // Deepgram API Key
        stackView.addArrangedSubview(makeLabel("Deepgram API Key"))
        deepgramField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        deepgramField.placeholderString = "Enter Deepgram API key"
        deepgramField.widthAnchor.constraint(equalToConstant: 380).isActive = true
        stackView.addArrangedSubview(deepgramField)

        // OpenRouter API Key
        stackView.addArrangedSubview(makeLabel("OpenRouter API Key"))
        openRouterField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        openRouterField.placeholderString = "Enter OpenRouter API key"
        openRouterField.widthAnchor.constraint(equalToConstant: 380).isActive = true
        stackView.addArrangedSubview(openRouterField)

        // Model
        stackView.addArrangedSubview(makeLabel("LLM Model (OpenRouter model ID)"))
        modelField = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        modelField.widthAnchor.constraint(equalToConstant: 380).isActive = true
        stackView.addArrangedSubview(modelField)

        // Dictation Mode
        stackView.addArrangedSubview(makeLabel("Dictation Mode"))
        modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        modePopup.addItems(withTitles: ["Toggle (press to start/stop)", "Hold to Talk"])
        stackView.addArrangedSubview(modePopup)

        // Text Insertion Method
        stackView.addArrangedSubview(makeLabel("Text Insertion Method"))
        insertionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        insertionPopup.addItems(withTitles: ["Clipboard Paste (recommended)", "Accessibility API"])
        stackView.addArrangedSubview(insertionPopup)

        // History Path
        stackView.addArrangedSubview(makeLabel("Transcription History Path"))
        historyPathField = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        historyPathField.widthAnchor.constraint(equalToConstant: 380).isActive = true
        stackView.addArrangedSubview(historyPathField)

        // Launch at Login
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
        stackView.addArrangedSubview(launchAtLoginCheckbox)

        // Save button
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r" // Enter
        stackView.addArrangedSubview(saveButton)
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        return label
    }

    private func loadValues() {
        deepgramField.stringValue = settings.deepgramApiKey ?? ""
        openRouterField.stringValue = settings.openRouterApiKey ?? ""
        modelField.stringValue = settings.llmModel
        modePopup.selectItem(at: settings.dictationMode == .toggle ? 0 : 1)
        insertionPopup.selectItem(at: settings.insertionMethod == .clipboard ? 0 : 1)
        historyPathField.stringValue = settings.historyPath
        launchAtLoginCheckbox.state = settings.launchAtLogin ? .on : .off
    }

    @objc private func saveSettings() {
        let dgKey = deepgramField.stringValue
        let orKey = openRouterField.stringValue

        if !dgKey.isEmpty { settings.deepgramApiKey = dgKey }
        if !orKey.isEmpty { settings.openRouterApiKey = orKey }

        settings.llmModel = modelField.stringValue
        settings.dictationMode = modePopup.indexOfSelectedItem == 0 ? .toggle : .holdToTalk
        settings.insertionMethod = insertionPopup.indexOfSelectedItem == 0 ? .clipboard : .accessibility
        settings.historyPath = historyPathField.stringValue
        settings.launchAtLogin = launchAtLoginCheckbox.state == .on

        onSettingsSaved?()
        window?.close()
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/GhostType/UI/SettingsWindowController.swift
git commit -m "feat: add SettingsWindowController with API key and mode configuration"
```

### Task 13: Wire AppDelegate — Connect All Components

**Files:**
- Modify: `Sources/GhostType/AppDelegate.swift`

- [ ] **Step 1: Implement full AppDelegate**

```swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private let settings = SettingsManager()
    private lazy var logger = TranscriptionLogger(historyDirectory: settings.historyPath)
    private lazy var menuBar = MenuBarController(settings: settings, logger: logger)
    private var settingsWindow: SettingsWindowController?

    private var audioCapture: AudioCaptureManager?
    private var deepgram: DeepgramService?
    private var llmCleanup: LLMCleanupService?
    private let textInsertion = TextInsertionService()
    private let hotkeyManager = HotkeyManager()

    private var recordingStartTime: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up menu bar
        menuBar.setup()
        menuBar.onSettingsClicked = { [weak self] in self?.showSettings() }

        // Set up state change handler
        appState.onChange = { [weak self] state in
            DispatchQueue.main.async {
                self?.menuBar.updateIcon(for: state)
            }
        }

        // Set up hotkey
        hotkeyManager.mode = settings.dictationMode == .toggle ? .toggle : .holdToTalk
        hotkeyManager.onRecordStart = { [weak self] in self?.startDictation() }
        hotkeyManager.onRecordStop = { [weak self] in self?.stopDictation() }

        if !hotkeyManager.start() {
            showAccessibilityAlert()
        }

        // Show settings if no API keys
        if !settings.hasRequiredApiKeys {
            showSettings()
        }
    }

    // MARK: - Dictation Pipeline

    private func startDictation() {
        guard appState.transition(to: .recording) else { return }
        guard let apiKey = settings.deepgramApiKey else {
            appState.transition(to: .idle)
            showSettings()
            return
        }

        recordingStartTime = Date()

        // Set up Deepgram
        deepgram = DeepgramService(apiKey: apiKey)
        deepgram?.onError = { [weak self] error in
            print("Deepgram error: \(error)")
            DispatchQueue.main.async { self?.appState.transition(to: .idle) }
        }
        deepgram?.startStreaming()

        // Set up audio capture
        audioCapture = AudioCaptureManager()
        audioCapture?.onAudioData = { [weak self] data in
            self?.deepgram?.sendAudio(data)
        }

        do {
            try audioCapture?.startCapturing()
        } catch {
            print("Audio capture error: \(error)")
            appState.transition(to: .idle)
        }
    }

    private func stopDictation() {
        guard appState.transition(to: .processing) else { return }

        // Stop audio capture and tear down to prevent tap leak on next cycle
        audioCapture?.stopCapturing()
        let capturedDeepgram = deepgram
        audioCapture = nil
        deepgram = nil

        // Get final transcript from Deepgram
        capturedDeepgram?.stopStreaming { [weak self] rawTranscript in
            guard let self = self else { return }

            if rawTranscript.isEmpty {
                DispatchQueue.main.async { self.appState.transition(to: .idle) }
                return
            }

            // Clean up via LLM
            guard let orKey = self.settings.openRouterApiKey else {
                // No OpenRouter key — insert raw
                self.insertAndLog(raw: rawTranscript, cleaned: rawTranscript)
                return
            }

            let cleanup = LLMCleanupService(apiKey: orKey, model: self.settings.llmModel)
            cleanup.cleanup(rawTranscript) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let cleaned):
                    self.insertAndLog(raw: rawTranscript, cleaned: cleaned)
                case .failure(let error):
                    print("LLM cleanup error: \(error)")
                    // Fallback: insert raw transcript
                    self.insertAndLog(raw: rawTranscript, cleaned: rawTranscript)
                }
            }
        }
    }

    private func insertAndLog(raw: String, cleaned: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.appState.transition(to: .inserting)

            // Insert text
            self.textInsertion.insertText(cleaned, method: self.settings.insertionMethod)

            // Log transcription
            let duration = Int((Date().timeIntervalSince(self.recordingStartTime ?? Date())) * 1000)
            let entry = TranscriptionEntry(
                timestamp: Date(),
                rawTranscript: raw,
                cleanedText: cleaned,
                focusedApp: TextInsertionService.focusedAppBundleId() ?? "unknown",
                model: self.settings.llmModel,
                durationMs: duration
            )
            try? self.logger.log(entry)
            self.menuBar.refreshMenu()

            // Back to idle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.appState.transition(to: .idle)
            }
        }
    }

    // MARK: - UI

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings)
            settingsWindow?.onSettingsSaved = { [weak self] in
                guard let self = self else { return }
                // Update hotkey mode from settings
                self.hotkeyManager.mode = self.settings.dictationMode == .toggle ? .toggle : .holdToTalk
            }
        }
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "GhostType needs Accessibility permission to register global hotkeys and paste text. Please enable it in System Settings > Privacy & Security > Accessibility."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Run all tests**

Run: `swift test`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/GhostType/AppDelegate.swift
git commit -m "feat: wire AppDelegate — connect audio, Deepgram, LLM, insertion, and hotkey pipeline"
```

### Task 14: Final Verification

- [ ] **Step 1: Clean build**

Run: `swift build -c release`
Expected: Release build succeeds

- [ ] **Step 2: Run full test suite**

Run: `swift test`
Expected: All tests PASS

- [ ] **Step 3: Manual smoke test**

Run: `swift run` (or open the built `.app` bundle)

Verify the following:
1. Menu bar icon appears (mic icon)
2. Click icon → dropdown shows "Recent Transcriptions", "Settings...", "Quit GhostType"
3. Open Settings → all fields present (API keys, model, dictation mode, insertion method, history path, launch at login)
4. Enter API keys, save → settings window closes
5. Press hotkey (Option+Space) → icon turns red (recording)
6. Speak a sentence → press hotkey again → icon turns orange (processing) → text appears at cursor → icon returns to default
7. Check `~/.ghosttype/history/` for today's `.jsonl` file with the transcription entry
8. Click "Recent Transcriptions" → entry appears, click copies to clipboard

- [ ] **Step 4: Commit any remaining changes**

```bash
git add Sources/ Tests/
git commit -m "chore: final cleanup and verification"
```
