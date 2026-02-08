import CLISDK

@CLIProgram("gh")
public struct GhCLI {

    @CLICommand
    public struct Pr {

        @CLICommand
        public struct Diff {
            @Positional public var number: String
        }

        @CLICommand
        public struct View {
            @Positional public var number: String
            @Option("--json") public var json: String?
        }

        @CLICommand
        public struct List {
            @Option("--json") public var json: String?
            @Option("--limit") public var limit: String?
            @Option("--state") public var state: String?
            @Option("-R") public var repo: String?
            @Option("--search") public var search: String?
        }
    }

    @CLICommand
    public struct Repo {

        @CLICommand
        public struct View {
            @Positional public var repo: String?
            @Option("--json") public var json: String?
        }
    }

    @CLICommand
    public struct Api {
        @Positional public var endpoint: String
        @Option("-X") public var method: String?
        @Option("--jq") public var jq: String?
        @Option("-H") public var headers: [String]
        @Option("-f") public var fields: [String]
        @Option("-F") public var rawFields: [String]
    }
}
