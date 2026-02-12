import Foundation

/// Represents the Python environment used to run the Claude Agent script.
public struct PythonEnvironment: Sendable {
    public let agentScriptPath: String
    public let agentScriptDirectory: String
    public let pythonCommand: String

    public init(agentScriptPath: String) {
        self.agentScriptPath = agentScriptPath
        self.agentScriptDirectory = (agentScriptPath as NSString).deletingLastPathComponent
        let venvPython = "\(self.agentScriptDirectory)/.venv/bin/python3"
        self.pythonCommand = FileManager.default.fileExists(atPath: venvPython) ? venvPython : "python3"
    }
}
