import Foundation
import Logging
import Testing
@testable import LoggingSDK

struct FileLogHandlerTests {
    private func makeTempLogURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PRRadarTests-\(UUID().uuidString)")
        return dir.appendingPathComponent("test.log")
    }

    @Test func createsLogFileIfMissing() throws {
        // Arrange
        let logURL = makeTempLogURL()
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        var handler = FileLogHandler(label: "test", fileURL: logURL)
        handler.logLevel = .debug

        // Act
        handler.log(
            level: .info,
            message: "hello",
            metadata: nil,
            source: "test",
            file: #file,
            function: #function,
            line: #line
        )

        // Assert
        #expect(FileManager.default.fileExists(atPath: logURL.path))
    }

    @Test func appendsJSONLineEntries() throws {
        // Arrange
        let logURL = makeTempLogURL()
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        var handler = FileLogHandler(label: "test.append", fileURL: logURL)
        handler.logLevel = .debug

        // Act
        handler.log(level: .info, message: "first", metadata: nil, source: "test", file: #file, function: #function, line: #line)
        handler.log(level: .warning, message: "second", metadata: nil, source: "test", file: #file, function: #function, line: #line)

        // Assert
        let content = try String(contentsOf: logURL, encoding: .utf8)
        let lines = content.split(separator: "\n")
        #expect(lines.count == 2)
    }

    @Test func entriesAreValidJSONWithExpectedFields() throws {
        // Arrange
        let logURL = makeTempLogURL()
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }
        var handler = FileLogHandler(label: "PRRadar.Test", fileURL: logURL)
        handler.logLevel = .debug

        // Act
        handler.log(level: .error, message: "something failed", metadata: ["prNumber": "42"], source: "test", file: #file, function: #function, line: #line)

        // Assert
        let content = try String(contentsOf: logURL, encoding: .utf8)
        let data = try #require(content.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["timestamp"] is String)
        #expect(json["level"] as? String == "error")
        #expect(json["label"] as? String == "PRRadar.Test")
        #expect(json["message"] as? String == "something failed")

        let metadata = try #require(json["metadata"] as? [String: String])
        #expect(metadata["prNumber"] == "42")
    }
}
