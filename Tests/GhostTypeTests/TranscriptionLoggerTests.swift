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
