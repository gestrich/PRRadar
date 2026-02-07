import CLISDK

@CLIProgram("prradar")
public struct PRRadar {

    @CLICommand
    public struct Agent {

        @CLICommand
        public struct Diff {
            @Positional public var prNumber: String
            @Option("--repo-path") public var repoPath: String?
            @Flag("--github-diff") public var githubDiff: Bool = false
            @Option("--output-dir") public var outputDir: String?
        }

        @CLICommand
        public struct Rules {
            @Positional public var prNumber: String
            @Option("--rules-dir") public var rulesDir: String?
            @Option("--output-dir") public var outputDir: String?
        }

        @CLICommand
        public struct Evaluate {
            @Positional public var prNumber: String
            @Option("--rules") public var rules: String?
            @Option("--repo-path") public var repoPath: String?
            @Option("--output-dir") public var outputDir: String?
        }

        @CLICommand
        public struct Report {
            @Positional public var prNumber: String
            @Option("--min-score") public var minScore: String?
            @Option("--output-dir") public var outputDir: String?
        }

        @CLICommand
        public struct Comment {
            @Positional public var prNumber: String
            @Option("--repo") public var repo: String?
            @Option("--min-score") public var minScore: String?
            @Flag("-n") public var noInteractive: Bool = false
            @Flag("--dry-run") public var dryRun: Bool = false
            @Option("--output-dir") public var outputDir: String?
        }

        @CLICommand
        public struct Analyze {
            @Positional public var prNumber: String
            @Option("--rules-dir") public var rulesDir: String?
            @Option("--repo-path") public var repoPath: String?
            @Flag("--github-diff") public var githubDiff: Bool = false
            @Option("--stop-after") public var stopAfter: String?
            @Option("--skip-to") public var skipTo: String?
            @Flag("-n") public var noInteractive: Bool = false
            @Flag("--no-dry-run") public var noDryRun: Bool = false
            @Option("--min-score") public var minScore: String?
            @Option("--repo") public var repo: String?
            @Option("--output-dir") public var outputDir: String?
        }

        @CLICommand
        public struct Status {
            @Positional public var prNumber: String
            @Option("--output-dir") public var outputDir: String?
        }

        @CLICommand
        public struct ListPrs {
            @Option("--limit") public var limit: String?
            @Option("--state") public var state: String?
        }
    }
}
