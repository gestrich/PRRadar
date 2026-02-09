import CLISDK

@CLIProgram("python3")
public struct ClaudeBridge {
    @Positional public var scriptPath: String
}
