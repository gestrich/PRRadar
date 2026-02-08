import CLISDK

@CLIProgram("git")
public struct GitCLI {

    @CLICommand
    public struct Status {
        @Flag public var porcelain: Bool = false
    }

    @CLICommand
    public struct Fetch {
        @Positional public var remote: String
        @Positional public var branch: String
    }

    @CLICommand
    public struct Checkout {
        @Positional public var ref: String
    }

    @CLICommand
    public struct Clean {
        @Positional public var args: [String]
    }

    @CLICommand
    public struct Diff {
        @Flag public var noIndex: Bool = false
        @Flag public var noColor: Bool = false
        @Positional public var args: [String]
    }

    @CLICommand
    public struct Show {
        @Positional public var spec: String
    }

    @CLICommand
    public struct RevParse {
        @Flag public var gitDir: Bool = false
        @Flag public var showToplevel: Bool = false
        @Flag public var abbrevRef: Bool = false
        @Positional public var ref: String?
    }

    @CLICommand
    public struct Remote {
        @Positional public var args: [String]
    }
}
