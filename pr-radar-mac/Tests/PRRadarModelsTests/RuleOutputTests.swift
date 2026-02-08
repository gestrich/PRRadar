import Foundation
import Testing
@testable import PRRadarModels

@Suite("Rule Output JSON Parsing")
struct RuleOutputTests {

    // MARK: - AppliesTo

    @Test("AppliesTo decodes with file patterns and exclude patterns")
    func appliesToFullDecode() throws {
        let json = """
        {
            "file_patterns": ["*.swift", "*.py"],
            "exclude_patterns": ["*Tests*", "*Mock*"]
        }
        """.data(using: .utf8)!

        let appliesTo = try JSONDecoder().decode(AppliesTo.self, from: json)
        #expect(appliesTo.filePatterns == ["*.swift", "*.py"])
        #expect(appliesTo.excludePatterns == ["*Tests*", "*Mock*"])
    }

    @Test("AppliesTo decodes with only file patterns (exclude omitted)")
    func appliesToFileOnlyDecode() throws {
        let json = """
        {
            "file_patterns": ["*.swift"]
        }
        """.data(using: .utf8)!

        let appliesTo = try JSONDecoder().decode(AppliesTo.self, from: json)
        #expect(appliesTo.filePatterns == ["*.swift"])
        #expect(appliesTo.excludePatterns == nil)
    }

    // MARK: - GrepPatterns

    @Test("GrepPatterns decodes with all and any")
    func grepPatternsDecode() throws {
        let json = """
        {
            "all": ["import\\\\s+Foundation", "class\\\\s+\\\\w+"],
            "any": ["func\\\\s+test", "override"]
        }
        """.data(using: .utf8)!

        let grep = try JSONDecoder().decode(GrepPatterns.self, from: json)
        #expect(grep.all?.count == 2)
        #expect(grep.any?.count == 2)
    }

    @Test("GrepPatterns decodes with only any patterns")
    func grepPatternsAnyOnly() throws {
        let json = """
        {
            "any": ["performBlock", "dispatch_async"]
        }
        """.data(using: .utf8)!

        let grep = try JSONDecoder().decode(GrepPatterns.self, from: json)
        #expect(grep.all == nil)
        #expect(grep.any == ["performBlock", "dispatch_async"])
    }

    // MARK: - ReviewRule

    @Test("ReviewRule decodes full rule from Python's Rule.to_dict()")
    func reviewRuleFullDecode() throws {
        let json = """
        {
            "name": "error-handling",
            "file_path": "/rules/error-handling.md",
            "description": "Ensure proper error handling in async code",
            "category": "reliability",
            "focus_type": "method",
            "content": "# Error Handling\\n\\nAll async functions must use try/catch...",
            "model": "claude-sonnet-4-20250514",
            "documentation_link": "https://docs.example.com/error-handling",
            "relevant_claude_skill": "swift-testing",
            "rule_url": "https://github.com/org/rules/blob/main/error-handling.md",
            "applies_to": {
                "file_patterns": ["*.swift"],
                "exclude_patterns": ["*Tests*"]
            },
            "grep": {
                "any": ["async", "await", "Task\\\\s*\\\\{"]
            }
        }
        """.data(using: .utf8)!

        let rule = try JSONDecoder().decode(ReviewRule.self, from: json)
        #expect(rule.name == "error-handling")
        #expect(rule.filePath == "/rules/error-handling.md")
        #expect(rule.description == "Ensure proper error handling in async code")
        #expect(rule.category == "reliability")
        #expect(rule.focusType == .method)
        #expect(rule.content.contains("Error Handling"))
        #expect(rule.model == "claude-sonnet-4-20250514")
        #expect(rule.documentationLink == "https://docs.example.com/error-handling")
        #expect(rule.relevantClaudeSkill == "swift-testing")
        #expect(rule.ruleUrl == "https://github.com/org/rules/blob/main/error-handling.md")
        #expect(rule.appliesTo?.filePatterns == ["*.swift"])
        #expect(rule.appliesTo?.excludePatterns == ["*Tests*"])
        #expect(rule.grep?.any?.first == "async")
    }

    @Test("ReviewRule decodes minimal rule (optional fields omitted)")
    func reviewRuleMinimalDecode() throws {
        let json = """
        {
            "name": "naming-conventions",
            "file_path": "/rules/naming.md",
            "description": "Follow naming conventions",
            "category": "style",
            "focus_type": "file",
            "content": "Use camelCase for variables..."
        }
        """.data(using: .utf8)!

        let rule = try JSONDecoder().decode(ReviewRule.self, from: json)
        #expect(rule.name == "naming-conventions")
        #expect(rule.model == nil)
        #expect(rule.documentationLink == nil)
        #expect(rule.relevantClaudeSkill == nil)
        #expect(rule.ruleUrl == nil)
        #expect(rule.appliesTo == nil)
        #expect(rule.grep == nil)
    }

    @Test("ReviewRule round-trips through encode/decode")
    func reviewRuleRoundTrip() throws {
        let json = """
        {
            "name": "test-rule",
            "file_path": "/rules/test.md",
            "description": "Test rule",
            "category": "testing",
            "focus_type": "method",
            "content": "Rule content here",
            "model": "claude-sonnet-4-20250514",
            "applies_to": {
                "file_patterns": ["*.py"]
            }
        }
        """.data(using: .utf8)!

        let original = try JSONDecoder().decode(ReviewRule.self, from: json)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReviewRule.self, from: encoded)

        #expect(original.name == decoded.name)
        #expect(original.filePath == decoded.filePath)
        #expect(original.category == decoded.category)
        #expect(original.focusType == decoded.focusType)
        #expect(original.model == decoded.model)
    }

    @Test("Bare JSON array decodes as [ReviewRule] (all-rules.json format)")
    func bareRulesArrayDecode() throws {
        let json = """
        [
            {
                "name": "rule-1",
                "file_path": "/rules/1.md",
                "description": "First rule",
                "category": "correctness",
                "focus_type": "method",
                "content": "Check correctness"
            }
        ]
        """.data(using: .utf8)!

        let rules = try JSONDecoder().decode([ReviewRule].self, from: json)
        #expect(rules.count == 1)
        #expect(rules[0].name == "rule-1")
    }
}
