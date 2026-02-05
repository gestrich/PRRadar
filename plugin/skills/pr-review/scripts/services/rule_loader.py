"""Rule loader service.

Loads and filters code review rules from a directory of markdown files.
Rules are parsed once from YAML frontmatter into typed domain models.

Following Martin Fowler's Service Layer pattern with constructor-based
dependency injection.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from scripts.domain.rule import Rule


@dataclass
class RuleLoaderService:
    """Service for loading and filtering code review rules.

    Recursively loads rules from a directory and filters them based on
    file extensions and grep patterns.

    Attributes:
        rules_dir: Path to the directory containing rule markdown files
    """

    rules_dir: Path

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
            ValueError: If directory does not exist
        """
        path = Path(rules_dir)
        if not path.exists():
            raise ValueError(f"Rules directory does not exist: {rules_dir}")
        if not path.is_dir():
            raise ValueError(f"Rules path is not a directory: {rules_dir}")

        return cls(rules_dir=path)

    # ============================================================
    # Public API
    # ============================================================

    def load_all_rules(self) -> list[Rule]:
        """Load all rules from the rules directory.

        Recursively finds all .md files and parses them as rules.
        Files that fail to parse are skipped with a warning.

        Returns:
            List of parsed Rule instances
        """
        rules: list[Rule] = []
        md_files = sorted(self.rules_dir.rglob("*.md"))

        for md_file in md_files:
            try:
                rule = Rule.from_file(md_file)
                rules.append(rule)
            except Exception as e:
                print(f"Warning: Failed to parse rule {md_file}: {e}")

        return rules

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
