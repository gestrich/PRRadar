"""Domain enum for diff source selection.

This module defines the DiffSource enum used to select between different
diff acquisition strategies in the provider factory.
"""

from enum import Enum


class DiffSource(Enum):
    """Source for diff acquisition.

    Attributes:
        GITHUB_API: Use GitHub API for diff (default, no local repo required)
        LOCAL_GIT: Use local git for diff (requires local repo checkout)

    Note:
        Both sources use GitHub API for PR metadata (branch names, etc).
        Only the diff acquisition method changes.
    """

    GITHUB_API = "github"
    LOCAL_GIT = "local"

    @classmethod
    def from_string(cls, value: str) -> "DiffSource":
        """Parse DiffSource from string value.

        Args:
            value: String value ("github" or "local")

        Returns:
            Corresponding DiffSource enum value

        Raises:
            ValueError: If value is not a valid DiffSource

        Examples:
            >>> DiffSource.from_string("github")
            <DiffSource.GITHUB_API: 'github'>
            >>> DiffSource.from_string("local")
            <DiffSource.LOCAL_GIT: 'local'>
        """
        value_lower = value.lower()
        for member in cls:
            if member.value == value_lower:
                return member
        valid_values = [m.value for m in cls]
        raise ValueError(
            f"Invalid diff source: {value}. Must be one of: {', '.join(valid_values)}"
        )
