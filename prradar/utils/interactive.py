"""Interactive prompting utilities for agent commands.

Provides reusable prompt functions for interactive CLI workflows.
"""

from __future__ import annotations

from dataclasses import dataclass


# ============================================================
# Domain Models
# ============================================================


@dataclass
class PromptChoice:
    """A choice option for interactive prompts."""

    key: str
    label: str
    description: str


# ============================================================
# Prompt Functions
# ============================================================


def prompt_choice(
    message: str,
    choices: list[PromptChoice],
    default: str | None = None,
) -> str | None:
    """Prompt user to select from choices.

    Args:
        message: The prompt message to display
        choices: List of available choices
        default: Default choice key (highlighted in prompt)

    Returns:
        The selected choice key, or None on EOF
    """
    # Build choice hint string (e.g., "[y]es / [n]o / [q]uit")
    hints = []
    for c in choices:
        if default and c.key == default:
            hints.append(f"[{c.key.upper()}]{c.label[1:]}")
        else:
            hints.append(f"[{c.key}]{c.label[1:]}")
    hint_str = " / ".join(hints)

    valid_keys = {c.key.lower() for c in choices}
    valid_keys.update({c.label.lower() for c in choices})

    while True:
        try:
            response = input(f"{message} {hint_str}: ").strip().lower()
        except EOFError:
            return None

        # Handle empty response with default
        if not response and default:
            return default

        # Check for valid response
        for c in choices:
            if response in (c.key.lower(), c.label.lower()):
                return c.key

        # Invalid response
        valid_keys_str = ", ".join(f"'{c.key}'" for c in choices)
        print(f"  Please enter {valid_keys_str}")


def prompt_yes_no_quit(message: str, default: str | None = None) -> str | None:
    """Prompt user with yes/no/quit options.

    Args:
        message: The prompt message to display
        default: Default choice ('y', 'n', or 'q')

    Returns:
        'y', 'n', 'q', or None on EOF
    """
    choices = [
        PromptChoice("y", "yes", "Proceed with action"),
        PromptChoice("n", "no", "Skip this item"),
        PromptChoice("q", "quit", "Stop processing"),
    ]
    return prompt_choice(message, choices, default)


# ============================================================
# Display Functions
# ============================================================


def print_separator(char: str = "─", width: int = 60) -> None:
    """Print a horizontal separator line."""
    print(char * width)


def print_header(text: str, char: str = "─", width: int = 60) -> None:
    """Print text with separators above and below."""
    print_separator(char, width)
    print(text)
    print_separator(char, width)
