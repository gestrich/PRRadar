import Foundation
import PRRadarMacSDK
import CLISDK

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("Usage: prradar-cli <repo-path> <pr-number>")
    exit(1)
}

let repoPath = args[1]
let prNumber = args[2]

let client = CLIClient(defaultWorkingDirectory: repoPath)
let command = PRRadar.Agent.Diff(prNumber: prNumber, repoPath: repoPath)

do {
    let result = try await client.executeForResult(command)
    print(result.output)

    if result.isSuccess {
        let outputDir = "\(repoPath)/code-reviews/\(prNumber)/phase-1-pull-request"
        let files = try FileManager.default.contentsOfDirectory(atPath: outputDir).sorted()
        print("\nPhase 1 output files:")
        for file in files {
            print("  \(file)")
        }
    } else {
        print("Phase 1 failed (exit code \(result.exitCode))")
        exit(1)
    }
} catch {
    print("Error: \(error)")
    exit(1)
}
