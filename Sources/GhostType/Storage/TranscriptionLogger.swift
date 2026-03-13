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
