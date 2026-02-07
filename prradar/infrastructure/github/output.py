"""GitHub Actions output helpers."""

from __future__ import annotations

import os


def write_github_output(key: str, value: str) -> None:
    """Write a key-value pair to GITHUB_OUTPUT for job outputs.

    Handles multiline values using heredoc syntax.

    Args:
        key: Output variable name
        value: Output value (can be multiline)
    """
    output_file = os.environ.get("GITHUB_OUTPUT")
    if not output_file:
        print(f"GITHUB_OUTPUT not set, would output: {key}={value[:100]}...")
        return
    with open(output_file, "a") as f:
        if "\n" in value:
            f.write(f"{key}<<EOF\n{value}\nEOF\n")
        else:
            f.write(f"{key}={value}\n")


def write_github_step_summary(content: str) -> bool:
    """Write content to GITHUB_STEP_SUMMARY for job summary.

    Args:
        content: Markdown content to write to the summary

    Returns:
        True if written successfully, False otherwise
    """
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not summary_path:
        print("GITHUB_STEP_SUMMARY not set, skipping job summary")
        return False
    try:
        with open(summary_path, "a") as f:
            f.write(content)
        return True
    except OSError as e:
        print(f"Failed to write job summary: {e}")
        return False
