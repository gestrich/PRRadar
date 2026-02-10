import Foundation

/// Represents the Python environment used to run the Claude bridge script.
public struct PythonEnvironment: Sendable {
    public let bridgeScriptPath: String
    public let bridgeDirectory: String
    public let pythonCommand: String

    public init(bridgeScriptPath: String) {
        self.bridgeScriptPath = bridgeScriptPath
        self.bridgeDirectory = (bridgeScriptPath as NSString).deletingLastPathComponent
        let venvPython = "\(self.bridgeDirectory)/.venv/bin/python3"
        self.pythonCommand = FileManager.default.fileExists(atPath: venvPython) ? venvPython : "python3"
    }
}
