import CLISDK
import PRRadarMacSDK
import PRRadarConfigService

public struct PRRadarCLIRunner: Sendable {

    public init() {}

    /// Executes a PRRadar agent command with the given configuration and environment.
    ///
    /// Handles the `--output-dir` argument insertion required by the Python CLI parser
    /// (must appear after "agent" but before the subcommand).
    public func execute<C: CLICommand>(
        command: C,
        config: PRRadarConfig,
        environment: [String: String]
    ) async throws -> CLIResult where C.Program == PRRadar {
        let client = CLIClient(defaultWorkingDirectory: config.repoPath)

        var arguments = command.commandArguments
        if let agentIndex = arguments.firstIndex(of: "agent") {
            arguments.insert(
                contentsOf: ["--output-dir", config.resolvedOutputDir],
                at: agentIndex + 1
            )
        }

        let result = try await client.execute(
            command: config.prradarPath,
            arguments: arguments,
            environment: environment,
            printCommand: false
        )

        return CLIResult(
            exitCode: result.exitCode,
            output: result.output,
            errorOutput: result.errorOutput
        )
    }
}
