---
name: pr-radar-add-rule
description: Create a new PRRadar review rule. Use when the user wants to add a code review rule, create a violation check, or set up a new pattern to detect in PRs. Handles choosing the project config, rule directory, evaluation mode (AI/script/regex), file targeting, and grep filtering.
---

# Add a New PRRadar Rule

Create a new rule file for PRRadar's code review pipeline. Rules are markdown files with YAML frontmatter that define what to look for in PR diffs.

## Workflow

### Step 1: Determine the Target Project and Rule Directory

If the user didn't specify a project config or rule directory, help them choose:

1. Run `swift run PRRadarMacCLI config list` (from the `PRRadarLibrary/` directory) to show available configurations
2. Ask which config to use (or use the default if there's only one)
3. Each config has one or more **rule paths** (named directories where rules live). Show the available rule paths and ask which one to use
4. Rule paths can be relative (resolved against the repo root) or absolute paths

If the user already specified a directory (e.g., "add a rule to my experimental rules"), use that directly.

### Step 2: Gather Rule Details

Determine the following from the user's request or by asking:

- **What to check for** — the pattern, practice, or violation to detect
- **Which files it applies to** — file glob patterns like `["*.h"]`, `["*.swift", "*.m"]`
- **Evaluation mode** — how violations should be detected:
  - **AI** (default) — Claude evaluates the diff against the rule's markdown content
  - **Script** — a shell script runs against the file and outputs violations
  - **Regex** — a simple regex pattern flags matches on changed lines

If the user describes something that can be checked deterministically (like "flag uses of X macro" or "check for missing Y annotation"), suggest script or regex mode since they're faster and fully deterministic. If the check requires judgment or understanding context, suggest AI mode.

### Step 3: Choose the Subdirectory

Rules are organized into subdirectories within the rule path (e.g., `apis-apple/`, `safety/`, `clarity/`). List the existing subdirectories and either:
- Place the rule in an existing subdirectory that fits
- Create a new subdirectory if none fits
- Ask the user if it's unclear

### Step 4: Create the Rule File

Write a `.md` file with YAML frontmatter and a markdown body.

#### Frontmatter Template

```yaml
---
description: One-line summary of what the rule checks
category: correctness|safety|clarity|performance|api-usage
applies_to:
  file_patterns: ["*.h", "*.m"]
  exclude_patterns: ["**/Generated/**"]  # optional
grep:
  any: ["PATTERN_1", "PATTERN_2"]  # optional — at least one must match
  all: ["PATTERN_A"]               # optional — all must match
new_code_lines_only: true  # optional — only flag added lines
violation_script: path/to/script.sh  # optional — for script mode
violation_regex: "PATTERN"           # optional — for regex mode
violation_message: "Message for regex violations"  # optional
documentation_link: https://...     # optional
---
```

Key rules:
- `violation_script` and `violation_regex` are mutually exclusive
- If neither is set, the rule uses AI evaluation
- `grep` patterns are for pre-filtering which diffs the rule applies to (performance optimization) — they don't detect violations themselves
- File patterns use glob syntax: `*.swift` matches filename, `**/*.swift` matches any depth

#### Markdown Body

The body explains the rule with examples. For AI-evaluated rules, this content is the prompt sent to Claude — make it thorough with good/bad code examples. For script/regex rules, the body serves as documentation.

Include these sections:
- **Requirements** — what the rule enforces
- **Examples** — code snippets showing good and bad patterns
- **What to Check** — summary checklist for reviewers
- **GitHub Comment** — template comment posted on violations

### Step 5: Create Violation Script (if script mode)

If the rule uses `violation_script`, create the shell script:

1. Place it in the same subdirectory as the rule (or nearby)
2. The script receives three arguments: `FILE START_LINE END_LINE`
3. Output tab-delimited violations to stdout: `LINE\tCHAR\tSCORE[\tCOMMENT]`
   - LINE: line number (positive integer)
   - CHAR: column position (0 for line-level)
   - SCORE: severity 1-10
   - COMMENT: optional message (falls back to `violation_message` or `description`)
4. Exit 0 on success (even if no violations found), non-zero on error
5. Make the script executable: `chmod +x script.sh`

The script can scan the entire line range — PRRadar filters violations to only report those on changed lines in the diff.

### Step 6: Verify

After creating the rule:

1. Check that the rule file parses correctly by examining the frontmatter
2. If a script was created, test it against a sample file:
   ```bash
   ./script.sh /path/to/sample/file.h 1 999
   ```
3. Optionally run `swift run PRRadarMacCLI rules <PR_NUMBER> --config <config>` to verify the rule loads and matches expected files

## Example: Simple Regex Rule

```yaml
---
description: Do not use NS_ASSUME_NONNULL_BEGIN
category: correctness
violation_regex: "NS_ASSUME_NONNULL_BEGIN"
violation_message: "Do not use `NS_ASSUME_NONNULL_BEGIN`. Add explicit annotations instead."
applies_to:
  file_patterns: ["*.h"]
grep:
  any: ["NS_ASSUME_NONNULL_BEGIN"]
---

# Do Not Use NS_ASSUME_NONNULL

Do **not** use `NS_ASSUME_NONNULL_BEGIN` / `NS_ASSUME_NONNULL_END`...
```

## Example: Script Rule

```yaml
---
description: Ensures Objective-C collection types use lightweight generics
category: correctness
new_code_lines_only: true
violation_script: apis-apple/check-generics-objc.sh
applies_to:
  file_patterns: ["*.h", "*.m", "*.mm"]
grep:
  any: ["NSArray", "NSDictionary", "NSSet"]
---

# Objective-C Generics

Use lightweight generics on collection types...
```

## Example: AI Rule

```yaml
---
description: Prefer descriptive variable names over abbreviations
category: clarity
applies_to:
  file_patterns: ["*.swift"]
---

# Descriptive Variable Names

Variable names should clearly communicate their purpose...

## What to Check

1. Single-letter names outside loop counters
2. Vowel-removed abbreviations like `usr`, `msg`, `cfg`

## GitHub Comment

` ` `
Consider using a more descriptive variable name here.
` ` `
```
