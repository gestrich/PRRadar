"""Domain model for code review rules.

Rules are loaded from markdown files with YAML frontmatter. This module
provides the Rule domain model with parsing and matching capabilities.

Parse-once pattern: YAML frontmatter is parsed into type-safe models at
the boundary using from_file() factory methods.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING

import yaml

from prradar.domain.focus_area import FocusType

if TYPE_CHECKING:
    pass


# ============================================================
# Domain Models
# ============================================================


@dataclass
class AppliesTo:
    """Criteria for when a rule applies to code."""

    file_patterns: list[str] = field(default_factory=list)
    exclude_patterns: list[str] = field(default_factory=list)

    # --------------------------------------------------------
    # Factory Methods
    # --------------------------------------------------------

    @classmethod
    def from_dict(cls, data: dict | None) -> AppliesTo:
        """Parse applies_to criteria from YAML frontmatter.

        Args:
            data: Raw dictionary from YAML, or None if not specified

        Returns:
            Typed AppliesTo instance
        """
        if data is None:
            return cls()

        return cls(
            file_patterns=data.get("file_patterns", []),
            exclude_patterns=data.get("exclude_patterns", []),
        )

    # --------------------------------------------------------
    # Public API
    # --------------------------------------------------------

    def matches_file(self, file_path: str) -> bool:
        """Check if a file path matches the applies_to criteria.

        Args:
            file_path: Path to check (e.g., "src/api/handler.py")

        Returns:
            True if the file matches and is not excluded
        """
        import fnmatch

        # Check exclusions first - if excluded, always return False
        if self.exclude_patterns:
            if any(fnmatch.fnmatch(file_path, pattern) for pattern in self.exclude_patterns):
                return False

        # If no include patterns specified, match everything (that wasn't excluded)
        if not self.file_patterns:
            return True

        # Check file_patterns (glob patterns like "*.swift" or "ffm/**/*.swift")
        return any(fnmatch.fnmatch(file_path, pattern) for pattern in self.file_patterns)


@dataclass
class GrepPatterns:
    """Regex patterns for filtering diff segments.

    Used to pre-filter which diff segments a rule should evaluate.
    This reduces unnecessary AI calls by skipping segments that
    clearly don't match the rule's focus.

    Patterns are Python regular expressions (re module syntax).
    """

    all_patterns: list[str] = field(default_factory=list)
    any_patterns: list[str] = field(default_factory=list)

    # --------------------------------------------------------
    # Factory Methods
    # --------------------------------------------------------

    @classmethod
    def from_dict(cls, data: dict | None) -> GrepPatterns:
        """Parse regex patterns from YAML frontmatter.

        Args:
            data: Raw dictionary from YAML with 'all' and/or 'any' keys,
                  or None if not specified. Values are regex patterns.

        Returns:
            Typed GrepPatterns instance
        """
        if data is None:
            return cls()

        return cls(
            all_patterns=data.get("all", []),
            any_patterns=data.get("any", []),
        )

    # --------------------------------------------------------
    # Public API
    # --------------------------------------------------------

    def matches(self, text: str) -> bool:
        """Check if text matches the grep pattern criteria.

        Args:
            text: Text to search (typically a diff segment)

        Returns:
            True if patterns match (or no patterns specified):
            - If all_patterns: ALL must match
            - If any_patterns: at least ONE must match
            - If both: both conditions must be satisfied
            - If neither: returns True (no filtering)
        """
        if not self.all_patterns and not self.any_patterns:
            return True

        all_match = self._check_all_patterns(text)
        any_match = self._check_any_patterns(text)

        return all_match and any_match

    def has_patterns(self) -> bool:
        """Check if any grep patterns are defined."""
        return bool(self.all_patterns or self.any_patterns)

    # --------------------------------------------------------
    # Private Methods
    # --------------------------------------------------------

    def _check_all_patterns(self, text: str) -> bool:
        """Check if ALL patterns match the text."""
        if not self.all_patterns:
            return True

        return all(
            re.search(pattern, text, re.MULTILINE) for pattern in self.all_patterns
        )

    def _check_any_patterns(self, text: str) -> bool:
        """Check if ANY pattern matches the text."""
        if not self.any_patterns:
            return True

        return any(
            re.search(pattern, text, re.MULTILINE) for pattern in self.any_patterns
        )


@dataclass
class Rule:
    """A code review rule loaded from a markdown file.

    Rules consist of:
    - Metadata from YAML frontmatter (description, category, applies_to, grep, model, documentation_link, relevant_claude_skill)
    - Content from the markdown body (instructions for evaluation)
    """

    name: str
    file_path: str
    description: str
    category: str
    applies_to: AppliesTo
    grep: GrepPatterns
    content: str
    focus_type: FocusType = FocusType.FILE
    model: str | None = None
    documentation_link: str | None = None
    relevant_claude_skill: str | None = None
    rule_url: str | None = None

    # --------------------------------------------------------
    # Factory Methods
    # --------------------------------------------------------

    @classmethod
    def from_file(cls, file_path: Path) -> Rule:
        """Load a rule from a markdown file with YAML frontmatter.

        Args:
            file_path: Path to the markdown rule file

        Returns:
            Typed Rule instance

        Raises:
            ValueError: If the file cannot be parsed
        """
        text = file_path.read_text()
        frontmatter, content = cls._parse_frontmatter(text)

        focus_type_str = frontmatter.get("focus_type", "file")
        try:
            focus_type = FocusType(focus_type_str)
        except ValueError:
            focus_type = FocusType.FILE

        return cls(
            name=file_path.stem,
            file_path=str(file_path),
            description=frontmatter.get("description", ""),
            category=frontmatter.get("category", ""),
            applies_to=AppliesTo.from_dict(frontmatter.get("applies_to")),
            grep=GrepPatterns.from_dict(frontmatter.get("grep")),
            content=content.strip(),
            focus_type=focus_type,
            model=frontmatter.get("model"),
            documentation_link=frontmatter.get("documentation_link"),
            relevant_claude_skill=frontmatter.get("relevantClaudeSkill"),
        )

    @classmethod
    def from_dict(cls, data: dict) -> Rule:
        """Parse a rule from a dictionary (e.g., from JSON).

        Args:
            data: Dictionary with rule data

        Returns:
            Typed Rule instance
        """
        focus_type_str = data.get("focus_type", "file")
        try:
            focus_type = FocusType(focus_type_str)
        except ValueError:
            focus_type = FocusType.FILE

        return cls(
            name=data.get("name", ""),
            file_path=data.get("file_path", ""),
            description=data.get("description", ""),
            category=data.get("category", ""),
            applies_to=AppliesTo.from_dict(data.get("applies_to")),
            grep=GrepPatterns.from_dict(data.get("grep")),
            content=data.get("content", ""),
            focus_type=focus_type,
            model=data.get("model"),
            documentation_link=data.get("documentation_link"),
            relevant_claude_skill=data.get("relevant_claude_skill"),
            rule_url=data.get("rule_url"),
        )

    # --------------------------------------------------------
    # Serialization
    # --------------------------------------------------------

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        result = {
            "name": self.name,
            "file_path": self.file_path,
            "description": self.description,
            "category": self.category,
            "focus_type": self.focus_type.value,
            "content": self.content,
        }

        if self.model:
            result["model"] = self.model

        if self.documentation_link:
            result["documentation_link"] = self.documentation_link

        if self.relevant_claude_skill:
            result["relevant_claude_skill"] = self.relevant_claude_skill

        if self.rule_url:
            result["rule_url"] = self.rule_url

        if self.applies_to.file_patterns or self.applies_to.exclude_patterns:
            applies_to_dict: dict = {}
            if self.applies_to.file_patterns:
                applies_to_dict["file_patterns"] = self.applies_to.file_patterns
            if self.applies_to.exclude_patterns:
                applies_to_dict["exclude_patterns"] = self.applies_to.exclude_patterns
            result["applies_to"] = applies_to_dict

        if self.grep.has_patterns():
            grep_dict: dict = {}
            if self.grep.all_patterns:
                grep_dict["all"] = self.grep.all_patterns
            if self.grep.any_patterns:
                grep_dict["any"] = self.grep.any_patterns
            result["grep"] = grep_dict

        return result

    # --------------------------------------------------------
    # Public API
    # --------------------------------------------------------

    def applies_to_file(self, file_path: str) -> bool:
        """Check if this rule applies to a given file.

        Args:
            file_path: Path to check

        Returns:
            True if the rule applies based on file extension criteria
        """
        return self.applies_to.matches_file(file_path)

    def matches_diff_segment(self, diff_text: str) -> bool:
        """Check if a diff segment matches the grep patterns.

        Args:
            diff_text: The diff segment text to check

        Returns:
            True if the segment matches (or no patterns defined)
        """
        return self.grep.matches(diff_text)

    def should_evaluate(self, file_path: str, diff_text: str) -> bool:
        """Check if this rule should be evaluated for a file and diff.

        Combines file extension and grep pattern matching.

        Args:
            file_path: Path to the file
            diff_text: The diff segment text

        Returns:
            True if the rule should be evaluated
        """
        return self.applies_to_file(file_path) and self.matches_diff_segment(diff_text)

    # --------------------------------------------------------
    # Private Methods
    # --------------------------------------------------------

    @staticmethod
    def _parse_frontmatter(text: str) -> tuple[dict, str]:
        """Parse YAML frontmatter from markdown text.

        Args:
            text: Full markdown text with optional frontmatter

        Returns:
            Tuple of (frontmatter dict, remaining content)
        """
        if not text.startswith("---"):
            return {}, text

        parts = text.split("---", 2)
        if len(parts) < 3:
            return {}, text

        try:
            frontmatter = yaml.safe_load(parts[1]) or {}
        except yaml.YAMLError:
            frontmatter = {}

        content = parts[2]
        return frontmatter, content
