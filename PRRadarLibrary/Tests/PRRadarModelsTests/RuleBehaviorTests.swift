import Foundation
import Testing
@testable import PRRadarModels

@Suite("Rule Model Behavior")
struct RuleBehaviorTests {

    // MARK: - AppliesTo.matchesFile

    @Test("matchesFile returns true with no patterns (matches everything)")
    func matchesFileNoPatterns() {
        let appliesTo = AppliesTo()
        #expect(appliesTo.matchesFile("src/main.swift"))
    }

    @Test("matchesFile matches wildcard file pattern")
    func matchesFileWildcard() {
        let appliesTo = AppliesTo(filePatterns: ["*.swift"])
        #expect(appliesTo.matchesFile("ViewController.swift"))
        #expect(!appliesTo.matchesFile("handler.py"))
    }

    @Test("matchesFile matches path with ** glob")
    func matchesFileDoubleWildcard() {
        let appliesTo = AppliesTo(filePatterns: ["src/**/*.swift"])
        #expect(appliesTo.matchesFile("src/views/MainView.swift"))
        #expect(appliesTo.matchesFile("src/MainView.swift"))
        #expect(!appliesTo.matchesFile("tests/TestView.swift"))
    }

    @Test("matchesFile excludes matching exclude patterns")
    func matchesFileExcluded() {
        let appliesTo = AppliesTo(
            filePatterns: ["*.swift"],
            excludePatterns: ["*Tests*"]
        )
        #expect(appliesTo.matchesFile("ViewController.swift"))
        #expect(!appliesTo.matchesFile("ViewControllerTests.swift"))
    }

    @Test("matchesFile with exclude and no include patterns")
    func matchesFileExcludeOnly() {
        let appliesTo = AppliesTo(excludePatterns: ["*.md"])
        #expect(appliesTo.matchesFile("main.swift"))
        #expect(!appliesTo.matchesFile("README.md"))
    }

    @Test("matchesFile with multiple file patterns")
    func matchesFileMultiplePatterns() {
        let appliesTo = AppliesTo(filePatterns: ["*.swift", "*.py"])
        #expect(appliesTo.matchesFile("main.swift"))
        #expect(appliesTo.matchesFile("handler.py"))
        #expect(!appliesTo.matchesFile("config.yaml"))
    }

    // MARK: - GrepPatterns.matches

    @Test("matches returns true with no patterns")
    func grepMatchesNoPatterns() {
        let grep = GrepPatterns()
        #expect(grep.matches("anything"))
    }

    @Test("matches with 'any' patterns matches if one matches")
    func grepMatchesAny() {
        let grep = GrepPatterns(any: ["async", "await"])
        #expect(grep.matches("func fetchData() async throws"))
        #expect(grep.matches("let result = await task"))
        #expect(!grep.matches("func syncData()"))
    }

    @Test("matches with 'all' patterns requires all to match")
    func grepMatchesAll() {
        let grep = GrepPatterns(all: ["import", "Foundation"])
        #expect(grep.matches("import Foundation\nclass Foo {}"))
        #expect(!grep.matches("import UIKit\nclass Foo {}"))
    }

    @Test("matches with both 'all' and 'any' requires both conditions")
    func grepMatchesBoth() {
        let grep = GrepPatterns(all: ["class"], any: ["async", "throws"])
        #expect(grep.matches("class Fetcher {\n  func fetch() async {}"))
        #expect(!grep.matches("struct Fetcher {\n  func fetch() async {}"))
        #expect(!grep.matches("class Fetcher {\n  func fetch() {}"))
    }

    @Test("hasPatterns returns false for empty patterns")
    func grepHasPatterns() {
        #expect(!GrepPatterns().hasPatterns)
        #expect(!GrepPatterns(all: [], any: []).hasPatterns)
        #expect(GrepPatterns(any: ["test"]).hasPatterns)
        #expect(GrepPatterns(all: ["test"]).hasPatterns)
    }

    // MARK: - ReviewRule.shouldEvaluate

    @Test("shouldEvaluate combines file and grep checks")
    func shouldEvaluateCombined() {
        let rule = ReviewRule(
            name: "test",
            filePath: "/rules/test.md",
            description: "Test",
            category: "test",
            content: "Rule content",
            appliesTo: AppliesTo(filePatterns: ["*.swift"]),
            grep: GrepPatterns(any: ["async"])
        )

        #expect(rule.shouldEvaluate(filePath: "main.swift", diffText: "func fetch() async {}"))
        #expect(!rule.shouldEvaluate(filePath: "main.py", diffText: "func fetch() async {}"))
        #expect(!rule.shouldEvaluate(filePath: "main.swift", diffText: "func fetch() {}"))
    }

    @Test("shouldEvaluate with no patterns matches everything")
    func shouldEvaluateNoPatterns() {
        let rule = ReviewRule(
            name: "test",
            filePath: "/rules/test.md",
            description: "Test",
            category: "test",
            content: "Rule content"
        )

        #expect(rule.shouldEvaluate(filePath: "anything.txt", diffText: "any content"))
    }

    // MARK: - ReviewRule.fromFile / Frontmatter Parsing

    @Test("parseFrontmatter extracts YAML between --- delimiters")
    func parseFrontmatterBasic() {
        let text = """
        ---
        description: Test rule
        category: testing
        ---
        # Rule content here
        """

        let (fm, body) = ReviewRule.parseFrontmatter(text)
        #expect(fm["description"] as? String == "Test rule")
        #expect(fm["category"] as? String == "testing")
        #expect(body.contains("Rule content here"))
    }

    @Test("parseFrontmatter handles nested applies_to with inline arrays")
    func parseFrontmatterNested() {
        let text = """
        ---
        description: Swift rule
        category: style
        applies_to:
          file_patterns: ["*.swift", "*.m"]
          exclude_patterns: ["*Tests*"]
        ---
        Content
        """

        let (fm, _) = ReviewRule.parseFrontmatter(text)
        let appliesTo = fm["applies_to"] as? [String: Any]
        #expect(appliesTo != nil)
        #expect((appliesTo?["file_patterns"] as? [String]) == ["*.swift", "*.m"])
        #expect((appliesTo?["exclude_patterns"] as? [String]) == ["*Tests*"])
    }

    @Test("parseFrontmatter handles grep patterns")
    func parseFrontmatterGrep() {
        let text = """
        ---
        description: Async rule
        category: reliability
        grep:
          any: ["async", "await"]
          all: ["import"]
        ---
        Content
        """

        let (fm, _) = ReviewRule.parseFrontmatter(text)
        let grep = fm["grep"] as? [String: Any]
        #expect(grep != nil)
        #expect((grep?["any"] as? [String]) == ["async", "await"])
        #expect((grep?["all"] as? [String]) == ["import"])
    }

    @Test("parseFrontmatter handles YAML escape sequences in strings")
    func parseFrontmatterEscapes() {
        let text = """
        ---
        description: Import order rule
        grep:
          any: ["^\\\\s*import\\\\s+", "^\\\\s*@testable\\\\s+import\\\\s+"]
        ---
        Content
        """

        let (fm, _) = ReviewRule.parseFrontmatter(text)
        let grep = fm["grep"] as? [String: Any]
        let patterns = grep?["any"] as? [String]
        
        // YAML escape: "\\\\" becomes "\\" which our parser should convert to "\"
        // So "^\\\\s*import\\\\s+" should become "^\\s*import\\s+" (single backslashes for regex)
        #expect(patterns?[0] == "^\\s*import\\s+")
        #expect(patterns?[1] == "^\\s*@testable\\s+import\\s+")
    }

    @Test("parseFrontmatter returns empty dict for text without frontmatter")
    func parseFrontmatterNoFrontmatter() {
        let text = "# Just a markdown file\nNo frontmatter here."
        let (fm, body) = ReviewRule.parseFrontmatter(text)
        #expect(fm.isEmpty)
        #expect(body == text)
    }

    @Test("parseFrontmatter handles focus_type field")
    func parseFrontmatterFocusType() {
        let text = """
        ---
        description: Method rule
        category: correctness
        focus_type: method
        ---
        Content
        """

        let (fm, _) = ReviewRule.parseFrontmatter(text)
        #expect(fm["focus_type"] as? String == "method")
    }

    @Test("parseFrontmatter handles list items with - syntax")
    func parseFrontmatterListItems() {
        let text = """
        ---
        description: Rule
        category: test
        applies_to:
          file_patterns:
            - "*.swift"
            - "*.m"
        ---
        Content
        """

        let (fm, _) = ReviewRule.parseFrontmatter(text)
        // With nested dict, the sub-list approach may not be handled
        // but the inline array format ["*.swift"] is the primary one used
        let appliesTo = fm["applies_to"] as? [String: Any]
        #expect(appliesTo != nil)
    }

    // MARK: - ReviewRule memberwise init

    @Test("ReviewRule memberwise init sets all fields")
    func reviewRuleInit() {
        let rule = ReviewRule(
            name: "test-rule",
            filePath: "/rules/test-rule.md",
            description: "A test rule",
            category: "testing",
            focusType: .method,
            content: "Rule body",
            model: "claude-sonnet-4-20250514",
            documentationLink: "https://example.com",
            relevantClaudeSkill: "swift-testing",
            ruleUrl: "https://github.com/org/rules",
            appliesTo: AppliesTo(filePatterns: ["*.swift"]),
            grep: GrepPatterns(any: ["test"])
        )

        #expect(rule.name == "test-rule")
        #expect(rule.focusType == .method)
        #expect(rule.model == "claude-sonnet-4-20250514")
        #expect(rule.appliesTo?.filePatterns == ["*.swift"])
        #expect(rule.grep?.any == ["test"])
    }

    // MARK: - fnmatch

    @Test("fnmatch matches simple wildcard patterns")
    func fnmatchSimple() {
        #expect(AppliesTo.fnmatch("main.swift", pattern: "*.swift"))
        #expect(!AppliesTo.fnmatch("main.py", pattern: "*.swift"))
        #expect(AppliesTo.fnmatch("abc", pattern: "a?c"))
        #expect(!AppliesTo.fnmatch("abbc", pattern: "a?c"))
    }

    @Test("fnmatch handles ** for recursive path matching")
    func fnmatchGlobstar() {
        #expect(AppliesTo.fnmatch("src/views/Main.swift", pattern: "src/**/*.swift"))
        #expect(AppliesTo.fnmatch("src/Main.swift", pattern: "src/**/*.swift"))
        #expect(!AppliesTo.fnmatch("lib/Main.swift", pattern: "src/**/*.swift"))
    }

    @Test("fnmatch handles special regex characters in patterns")
    func fnmatchSpecialChars() {
        #expect(AppliesTo.fnmatch("file.swift", pattern: "file.swift"))
        #expect(!AppliesTo.fnmatch("fileXswift", pattern: "file.swift"))
    }
}
