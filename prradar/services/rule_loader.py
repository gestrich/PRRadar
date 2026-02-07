"""Rule loader service.

Loads and filters code review rules from a directory of markdown files.
Rules are parsed once from YAML frontmatter into typed domain models.

Following Martin Fowler's Service Layer pattern with constructor-based
dependency injection.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from prradar.domain.diff import Hunk
from prradar.domain.focus_area import FocusArea
from prradar.domain.rule import Rule
from prradar.infrastructure.git.git_utils import GitError, GitFileInfo, get_git_file_info


@dataclass
class RuleLoaderService:
    """Service for loading and filtering code review rules.

    Recursively loads rules from a directory and filters them based on
    file extensions and grep patterns.

    Attributes:
        rules_dir: Path to the directory containing rule markdown files
        git_info: Git repository information for the rules directory
    """

    rules_dir: Path
    git_info: GitFileInfo

    # ============================================================
    # Factory Methods
    # ============================================================

    @classmethod
    def create(cls, rules_dir: str | Path) -> RuleLoaderService:
        """Create a RuleLoaderService from a directory path.

        Args:
            rules_dir: Path to rules directory (string or Path)

        Returns:
            Configured RuleLoaderService instance

        Raises:
            ValueError: If directory does not exist or is not in a valid
                git repository with a GitHub remote
        """
        path = Path(rules_dir)
        if not path.exists():
            raise ValueError(f"Rules directory does not exist: {rules_dir}")
        if not path.is_dir():
            raise ValueError(f"Rules path is not a directory: {rules_dir}")

        try:
            git_info = get_git_file_info(str(path))
        except GitError as e:
            raise ValueError(
                f"Rules directory must be in a git repository with a valid remote: {e}"
            )

        if "github.com" not in git_info.repo_url:
            raise ValueError(
                f"Rules directory must be in a GitHub repository. "
                f"Found remote: {git_info.repo_url}"
            )

        return cls(rules_dir=path, git_info=git_info)

    # ============================================================
    # Public API
    # ============================================================

    def load_all_rules(self) -> list[Rule]:
        """Load all rules from the rules directory.

        Recursively finds all .md files and parses them as rules.
        Files that fail to parse are skipped with a warning.

        Returns:
            List of parsed Rule instances with rule_url populated
        """
        rules: list[Rule] = []
        md_files = sorted(self.rules_dir.rglob("*.md"))

        for md_file in md_files:
            try:
                rule = Rule.from_file(md_file)
                rule.rule_url = self._build_rule_url(md_file)
                rules.append(rule)
            except Exception as e:
                print(f"Warning: Failed to parse rule {md_file}: {e}")

        return rules

    def _build_rule_url(self, rule_file: Path) -> str:
        """Build the GitHub URL for a rule file.

        Uses the git_info from the rules directory to construct the URL.

        Args:
            rule_file: Path to the rule markdown file

        Returns:
            GitHub URL to view the rule file
        """
        file_info = get_git_file_info(str(rule_file))
        return file_info.to_github_url()

    def filter_rules_for_file(
        self,
        rules: list[Rule],
        file_path: str,
    ) -> list[Rule]:
        """Filter rules that apply to a specific file.

        Args:
            rules: List of rules to filter
            file_path: File path to check against applies_to criteria

        Returns:
            Rules that apply to the file based on file_patterns
        """
        return [rule for rule in rules if rule.applies_to_file(file_path)]

    def filter_rules_for_segment(
        self,
        rules: list[Rule],
        file_path: str,
        diff_text: str,
    ) -> list[Rule]:
        """Filter rules that should be evaluated for a code segment.

        Combines file extension filtering and grep pattern matching.

        Args:
            rules: List of rules to filter
            file_path: File path of the segment
            diff_text: Diff content to match against grep patterns

        Returns:
            Rules that should be evaluated for this segment
        """
        return [rule for rule in rules if rule.should_evaluate(file_path, diff_text)]

    def filter_rules_for_focus_area(
        self,
        all_rules: list[Rule],
        focus_area: FocusArea,
    ) -> list[Rule]:
        """Filter rules applicable to a focus area.

        Grep patterns are matched against the focused content only
        (the lines within the focus area bounds), not the entire hunk.

        Args:
            all_rules: All loaded rules
            focus_area: The focus area to filter against

        Returns:
            List of rules that apply to this focus area
        """
        applicable_rules = []

        for rule in all_rules:
            if not rule.applies_to_file(focus_area.file_path):
                continue

            if rule.grep.has_patterns():
                focused_content = focus_area.get_focused_content()
                changed_content = Hunk.extract_changed_content(focused_content)
                if not rule.matches_diff_segment(changed_content):
                    continue

            applicable_rules.append(rule)

        return applicable_rules
