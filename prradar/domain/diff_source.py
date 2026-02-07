"""Domain enum for diff source selection.

This module defines the DiffSource enum used to select between different
diff acquisition strategies in the provider factory.
"""

from __future__ import annotations

from enum import Enum


class DiffSource(Enum):
    """Source for diff acquisition.

    Attributes:
        GITHUB: Use GitHub API for diff (opt-in via --github-diff)
        LOCAL: Use local git for diff (default)

    Note:
        Both sources use GitHub API for PR metadata (branch names, etc).
        Both sources checkout the PR branch locally.
        Only the diff text acquisition method changes.
    """

    GITHUB = "github"
    LOCAL = "local"

    @classmethod
    def from_string(cls, value: str) -> DiffSource:
        """Parse DiffSource from string value.

        Args:
            value: String value ("github" or "local")

        Returns:
            Corresponding DiffSource enum value

        Raises:
            ValueError: If value is not a valid DiffSource

        Examples:
            >>> DiffSource.from_string("github")
            <DiffSource.GITHUB: 'github'>
            >>> DiffSource.from_string("local")
            <DiffSource.LOCAL: 'local'>
        """
        value_lower = value.lower()
        for member in cls:
            if member.value == value_lower:
                return member
        valid_values = [m.value for m in cls]
        raise ValueError(
            f"Invalid diff source: {value}. Must be one of: {', '.join(valid_values)}"
        )
