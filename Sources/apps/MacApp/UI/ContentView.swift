import SwiftUI
import PRRadarMacSDK
import CLISDK

struct ContentView: View {

    @AppStorage("repoPath") private var repoPath = ""
    @AppStorage("prNumber") private var prNumber = ""
    @AppStorage("outputDir") private var outputDir = ""
    @State private var isRunning = false
    @State private var outputFiles: [String] = []
    @State private var errorMessage: String?
    @State private var logs = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Phase 1: Fetch PR Diff")
                .font(.title2)
                .bold()

            HStack {
                Text("Repo Path")
                    .frame(width: 80, alignment: .trailing)
                TextField("/path/to/repo", text: $repoPath)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("PR Number")
                    .frame(width: 80, alignment: .trailing)
                TextField("123", text: $prNumber)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Spacer()
            }

            HStack {
                Text("Output Dir")
                    .frame(width: 80, alignment: .trailing)
                TextField("~/Desktop/code-reviews", text: $outputDir)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Run Phase 1") {
                    Task { await runPhase1() }
                }
                .disabled(isRunning || repoPath.isEmpty || prNumber.isEmpty)

                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if !outputFiles.isEmpty {
                Divider()
                Text("Output Files")
                    .font(.headline)

                List(outputFiles, id: \.self) { file in
                    Text(file)
                        .font(.system(.body, design: .monospaced))
                }
            }

            if !logs.isEmpty {
                Divider()
                Text("Logs")
                    .font(.headline)
                ScrollView {
                    Text(logs)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
    }

    var venvBinPath: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ContentView.swift → UI/
            .deletingLastPathComponent() // → MacApp/
            .deletingLastPathComponent() // → apps/
            .deletingLastPathComponent() // → Sources/
            .deletingLastPathComponent() // → repo root
            .appendingPathComponent(".venv/bin")
            .path
    }

    var prradarEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        if env["HOME"] == nil {
            env["HOME"] = NSHomeDirectory()
        }
        let currentPath = env["PATH"] ?? ""
        let extraPaths = [
            venvBinPath,
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        return env
    }

    func runPhase1() async {
        isRunning = true
        outputFiles = []
        errorMessage = nil
        logs = "Looking for prradar in: \(venvBinPath)\n"

        let client = CLIClient(defaultWorkingDirectory: repoPath)
        let command = PRRadar.Agent.Diff(
            prNumber: prNumber,
            repoPath: repoPath
        )

        // --output-dir is on the parent `agent` parser, so it must come before the subcommand.
        // commandArguments produces ["agent", "diff", ...] — insert --output-dir after "agent".
        var arguments = command.commandArguments
        let resolvedOutputDir = outputDir.isEmpty ? "code-reviews" : outputDir
        if let agentIndex = arguments.firstIndex(of: "agent") {
            arguments.insert(contentsOf: ["--output-dir", resolvedOutputDir], at: agentIndex + 1)
        }

        logs += "Running: prradar \(arguments.joined(separator: " "))\n\n"

        do {
            let prradarPath = "\(venvBinPath)/prradar"
            let result = try await client.execute(
                command: prradarPath,
                arguments: arguments,
                environment: prradarEnvironment,
                printCommand: false
            )
            logs += result.output

            if result.isSuccess {
                let expandedOutputDir = NSString(string: resolvedOutputDir).expandingTildeInPath
                let absoluteOutputDir = NSString(string: expandedOutputDir).isAbsolutePath
                    ? expandedOutputDir
                    : "\(repoPath)/\(expandedOutputDir)"
                let phaseDir = "\(absoluteOutputDir)/\(prNumber)/phase-1-pull-request"
                let fm = FileManager.default
                if let files = try? fm.contentsOfDirectory(atPath: phaseDir) {
                    outputFiles = files.sorted()
                } else {
                    errorMessage = "Phase 1 completed but output directory not found at \(phaseDir)"
                }
            } else {
                errorMessage = "Phase 1 failed (exit code \(result.exitCode))"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }
}

#Preview {
    ContentView()
}
