import CLISDK

@CLIProgram("python3")
public struct ClaudeAgentProgram {
    @Positional public var scriptPath: String
}
