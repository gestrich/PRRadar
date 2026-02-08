import Foundation

public enum ClaudeBridgeError: Error {
    case bridgeScriptNotFound(String)
    case pythonNotFound
    case invalidInput(String)
    case bridgeFailed(String)
    case noResult
}

/// A streaming message parsed from a single JSON-line of bridge output.
enum BridgeMessage {
    case text(String)
    case toolUse(name: String)
    case result(output: [String: Any]?, costUsd: Double?, durationMs: Int?)

    init?(jsonLine: String) {
        guard let data = jsonLine.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else {
            return nil
        }

        switch type {
        case "text":
            self = .text(obj["content"] as? String ?? "")
        case "tool_use":
            self = .toolUse(name: obj["name"] as? String ?? "")
        case "result":
            self = .result(
                output: obj["output"] as? [String: Any],
                costUsd: obj["cost_usd"] as? Double,
                durationMs: obj["duration_ms"] as? Int
            )
        default:
            return nil
        }
    }
}

/// Request sent to the Claude bridge script via stdin.
public struct BridgeRequest: Sendable {
    public let prompt: String
    public let model: String
    public let tools: [String]?
    public let cwd: String?
    /// Pre-serialized JSON schema data for structured output.
    public let outputSchemaData: Data?

    public init(
        prompt: String,
        model: String = "claude-sonnet-4-20250514",
        tools: [String]? = nil,
        cwd: String? = nil,
        outputSchema: [String: Any]? = nil
    ) {
        self.prompt = prompt
        self.model = model
        self.tools = tools
        self.cwd = cwd
        if let outputSchema {
            self.outputSchemaData = try? JSONSerialization.data(withJSONObject: outputSchema)
        } else {
            self.outputSchemaData = nil
        }
    }

    func toJSON() throws -> Data {
        var dict: [String: Any] = [
            "prompt": prompt,
            "model": model,
        ]
        if let tools { dict["tools"] = tools }
        if let cwd { dict["cwd"] = cwd }
        if let outputSchemaData,
           let schema = try? JSONSerialization.jsonObject(with: outputSchemaData) {
            dict["output_schema"] = schema
        }
        return try JSONSerialization.data(withJSONObject: dict)
    }
}

/// Result of a Claude bridge invocation.
public struct BridgeResult: Sendable {
    /// The structured output as serialized JSON data (if any).
    public let outputData: Data?
    public let costUsd: Double
    public let durationMs: Int

    public init(outputData: Data?, costUsd: Double, durationMs: Int) {
        self.outputData = outputData
        self.costUsd = costUsd
        self.durationMs = durationMs
    }

    /// Parse the output data as a JSON dictionary.
    public func outputAsDictionary() -> [String: Any]? {
        guard let outputData else { return nil }
        return try? JSONSerialization.jsonObject(with: outputData) as? [String: Any]
    }
}

/// Wraps the Python claude_bridge.py script, piping JSON to stdin and reading JSON-lines from stdout.
///
/// Uses Foundation Process directly (not CLIClient) because the bridge requires stdin piping.
public struct ClaudeBridgeClient: Sendable {
    private let bridgeScriptPath: String
    private let pythonPath: String

    public init(bridgeScriptPath: String, pythonPath: String = "python3") {
        self.bridgeScriptPath = bridgeScriptPath
        self.pythonPath = pythonPath
    }

    /// Execute a bridge request and return the structured result.
    ///
    /// Streams the bridge script output, collects text messages, and returns
    /// the final result message with cost/duration metadata.
    public func execute(_ request: BridgeRequest) async throws -> BridgeResult {
        let inputData = try request.toJSON()

        let resolvedPython = try resolvePythonPath()

        guard FileManager.default.fileExists(atPath: bridgeScriptPath) else {
            throw ClaudeBridgeError.bridgeScriptNotFound(bridgeScriptPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedPython)
        process.arguments = [bridgeScriptPath]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        stdinPipe.fileHandleForWriting.write(inputData)
        stdinPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            throw ClaudeBridgeError.bridgeFailed(
                "Bridge exited with code \(process.terminationStatus): \(stderr)"
            )
        }

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let lines = stdout.components(separatedBy: "\n").filter { !$0.isEmpty }

        var resultOutputData: Data?
        var costUsd: Double = 0.0
        var durationMs: Int = 0

        for line in lines {
            guard let message = BridgeMessage(jsonLine: line) else { continue }
            switch message {
            case .text(let content):
                for textLine in content.components(separatedBy: "\n") {
                    print("      \(textLine)", terminator: "\n")
                }
            case .toolUse:
                break
            case .result(let output, let cost, let duration):
                if let output {
                    resultOutputData = try? JSONSerialization.data(withJSONObject: output)
                }
                costUsd = cost ?? 0.0
                durationMs = duration ?? 0
            }
        }

        return BridgeResult(outputData: resultOutputData, costUsd: costUsd, durationMs: durationMs)
    }

    // MARK: - Private

    private func resolvePythonPath() throws -> String {
        if pythonPath.hasPrefix("/") {
            guard FileManager.default.fileExists(atPath: pythonPath) else {
                throw ClaudeBridgeError.pythonNotFound
            }
            return pythonPath
        }

        let commonPaths = [
            "/usr/bin/\(pythonPath)",
            "/usr/local/bin/\(pythonPath)",
            "/opt/homebrew/bin/\(pythonPath)",
        ]

        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = [pythonPath]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = Pipe()
        try which.run()
        which.waitUntilExit()

        if which.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let resolved = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !resolved.isEmpty {
                return resolved
            }
        }

        throw ClaudeBridgeError.pythonNotFound
    }
}
