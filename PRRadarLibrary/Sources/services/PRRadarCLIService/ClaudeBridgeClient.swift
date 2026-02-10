import CLISDK
import Foundation
import PRRadarConfigService

public enum ClaudeBridgeError: Error {
    case bridgeScriptNotFound(String)
    case pythonNotFound
    case invalidInput(String)
    case bridgeFailed(String)
    case noResult
}

/// A streaming event yielded by the bridge client as output arrives.
public enum BridgeStreamEvent: Sendable {
    case text(String)
    case toolUse(name: String)
    case result(BridgeResult)
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

/// Parses each JSON-line from the bridge script into a `BridgeStreamEvent`.
struct BridgeMessageParser: CLILineParser {
    func parse(line: String) throws -> BridgeStreamEvent? {
        guard let message = BridgeMessage(jsonLine: line) else { return nil }
        switch message {
        case .text(let content):
            return .text(content)
        case .toolUse(let name):
            return .toolUse(name: name)
        case .result(let output, let cost, let duration):
            var outputData: Data?
            if let output {
                outputData = try? JSONSerialization.data(withJSONObject: output)
            }
            let bridgeResult = BridgeResult(
                outputData: outputData,
                costUsd: cost ?? 0.0,
                durationMs: duration ?? 0
            )
            return .result(bridgeResult)
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
/// Uses `CLIClient.streamLines()` with a `BridgeMessageParser` for stdin piping and
/// line-buffered streaming.
public struct ClaudeBridgeClient: Sendable {
    private let bridgeScriptPath: String
    private let cliClient: CLIClient

    public init(bridgeScriptPath: String, cliClient: CLIClient) {
        self.bridgeScriptPath = bridgeScriptPath
        self.cliClient = cliClient
    }

    /// Stream bridge events as they arrive from the Python bridge process.
    ///
    /// Launches the bridge script, reads stdout line by line, and yields
    /// `BridgeStreamEvent` values in real time. The final event is always
    /// `.result` containing the structured output with cost/duration metadata.
    public func stream(_ request: BridgeRequest) -> AsyncThrowingStream<BridgeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard FileManager.default.fileExists(atPath: bridgeScriptPath) else {
                        throw ClaudeBridgeError.bridgeScriptNotFound(bridgeScriptPath)
                    }

                    let inputData = try request.toJSON()

                    let stream = await cliClient.streamLines(
                        command: "python3",
                        arguments: [bridgeScriptPath],
                        environment: PRRadarEnvironment.build(),
                        printCommand: false,
                        stdin: inputData,
                        parser: BridgeMessageParser()
                    )

                    for try await event in stream {
                        continuation.yield(event)
                    }

                    continuation.finish()
                } catch let error as CLIClientError {
                    continuation.finish(throwing: ClaudeBridgeError.bridgeFailed("\(error)"))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
