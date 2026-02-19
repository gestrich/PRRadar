import CLISDK
import ConcurrencySDK
import EnvironmentSDK
import Foundation

/// The resolved environment needed to run the Claude Agent subprocess.
///
/// Callers must resolve credentials before creating this value.
public struct ClaudeAgentEnvironment: Sendable {
    static let anthropicAPIKeyEnvVar = "ANTHROPIC_API_KEY"

    public let anthropicAPIKey: String
    let subprocessEnvironment: [String: String]

    public static func build(anthropicAPIKey: String) -> ClaudeAgentEnvironment {
        var env = ProcessInfo.processInfo.environment
        if env["HOME"] == nil {
            env["HOME"] = NSHomeDirectory()
        }
        let currentPath = env["PATH"] ?? ""
        let extraPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")

        let dotEnv = DotEnvironmentLoader.loadDotEnv()
        for (key, value) in dotEnv where env[key] == nil {
            env[key] = value
        }

        env[anthropicAPIKeyEnvVar] = anthropicAPIKey

        return ClaudeAgentEnvironment(anthropicAPIKey: anthropicAPIKey, subprocessEnvironment: env)
    }

    init(anthropicAPIKey: String, subprocessEnvironment: [String: String]) {
        self.anthropicAPIKey = anthropicAPIKey
        self.subprocessEnvironment = subprocessEnvironment
    }
}

/// A streaming event yielded by the Claude Agent client as output arrives.
public enum ClaudeAgentStreamEvent: Sendable {
    case text(String)
    case toolUse(name: String)
    case result(ClaudeAgentResult)
}

/// A streaming message parsed from a single JSON-line of Claude Agent output.
enum ClaudeAgentMessage {
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

/// Parses each JSON-line from the Claude Agent script into a `ClaudeAgentStreamEvent`.
struct ClaudeAgentMessageParser: CLILineParser {
    func parse(line: String) throws -> ClaudeAgentStreamEvent? {
        guard let message = ClaudeAgentMessage(jsonLine: line) else { return nil }
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
            let agentResult = ClaudeAgentResult(
                outputData: outputData,
                costUsd: cost ?? 0.0,
                durationMs: duration ?? 0
            )
            return .result(agentResult)
        }
    }
}

/// Request sent to the Claude Agent script via stdin.
public struct ClaudeAgentRequest: Sendable {
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

/// Result of a Claude Agent SDK invocation.
public struct ClaudeAgentResult: Sendable {
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

/// Wraps the Python claude_agent.py script, piping JSON to stdin and reading JSON-lines from stdout.
///
/// Uses `CLIClient.streamLines()` with a `ClaudeAgentMessageParser` for stdin piping and
/// line-buffered streaming.
public struct ClaudeAgentClient: Sendable {
    private let pythonEnvironment: PythonEnvironment
    private let cliClient: CLIClient
    private let environment: ClaudeAgentEnvironment

    public init(pythonEnvironment: PythonEnvironment, cliClient: CLIClient, environment: ClaudeAgentEnvironment) {
        self.pythonEnvironment = pythonEnvironment
        self.cliClient = cliClient
        self.environment = environment
    }

    private static let inactivityTimeout: TimeInterval = 120

    /// Stream events as they arrive from the Claude Agent process.
    ///
    /// Launches the agent script, reads stdout line by line, and yields
    /// `ClaudeAgentStreamEvent` values in real time. The final event is always
    /// `.result` containing the structured output with cost/duration metadata.
    ///
    /// The stream will fail with `ClaudeAgentError.agentTimedOut` when no
    /// events arrive for `inactivityTimeout` seconds.
    public func stream(_ request: ClaudeAgentRequest) -> AsyncThrowingStream<ClaudeAgentStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard FileManager.default.fileExists(atPath: pythonEnvironment.agentScriptPath) else {
                        throw ClaudeAgentError.scriptNotFound(pythonEnvironment.agentScriptPath)
                    }

                    let inputData = try request.toJSON()

                    let stream = await cliClient.streamLines(
                        command: pythonEnvironment.pythonCommand,
                        arguments: [pythonEnvironment.agentScriptPath],
                        environment: environment.subprocessEnvironment,
                        printCommand: false,
                        stdin: inputData,
                        parser: ClaudeAgentMessageParser()
                    )

                    let watchdog = InactivityWatchdog(
                        timeout: Self.inactivityTimeout,
                        onTimeout: {
                            continuation.finish(throwing: ClaudeAgentError.agentTimedOut(Int(Self.inactivityTimeout)))
                        }
                    )
                    await watchdog.start()

                    do {
                        for try await event in stream {
                            await watchdog.recordActivity()
                            continuation.yield(event)
                        }
                        await watchdog.cancel()
                        continuation.finish()
                    } catch {
                        await watchdog.cancel()
                        throw error
                    }
                } catch let error as CLIClientError {
                    continuation.finish(throwing: ClaudeAgentError.agentFailed("\(error)"))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

}

public enum ClaudeAgentError: LocalizedError {
    case scriptNotFound(String)
    case pythonNotFound
    case invalidInput(String)
    case agentFailed(String)
    case agentTimedOut(Int)
    case noResult
    case missingAPIKey

    public var errorDescription: String? {
        switch self {
        case .scriptNotFound(let path):
            return "Claude Agent script not found at \(path)"
        case .pythonNotFound:
            return "Python interpreter not found in Claude Agent venv"
        case .invalidInput(let detail):
            return "Invalid Claude Agent input: \(detail)"
        case .agentFailed(let detail):
            return "Claude Agent failed: \(detail)"
        case .agentTimedOut(let seconds):
            return "No response from Claude Agent for \(seconds) seconds"
        case .noResult:
            return "Claude Agent returned no result"
        case .missingAPIKey:
            return "\(ClaudeAgentEnvironment.anthropicAPIKeyEnvVar) not found in environment, .env, or Keychain"
        }
    }
}
