"""Parse Claude Code execution file outputs."""

from __future__ import annotations

import json
from pathlib import Path


def extract_structured_output(execution_data: dict | list) -> dict:
    """Extract structured_output from Claude's execution file format.

    The execution file can be in different formats:
    - Array format (verbose mode): structured_output is in the last item
    - Object format: structured_output is at the top level or nested in result

    Args:
        execution_data: Parsed JSON from the execution file

    Returns:
        The structured_output dict, or empty dict if not found
    """
    if isinstance(execution_data, list):
        if execution_data:
            last_item = execution_data[-1]
            if "structured_output" in last_item:
                return last_item["structured_output"]
            if "result" in last_item and "structured_output" in last_item["result"]:
                return last_item["result"]["structured_output"]
    elif isinstance(execution_data, dict):
        if "structured_output" in execution_data:
            return execution_data["structured_output"]
        if "result" in execution_data and "structured_output" in execution_data["result"]:
            return execution_data["result"]["structured_output"]
    return {}


def load_execution_file(path: str | Path) -> dict | list:
    """Load and parse a Claude execution file.

    Args:
        path: Path to the execution JSON file

    Returns:
        Parsed JSON data

    Raises:
        FileNotFoundError: If the file doesn't exist
        json.JSONDecodeError: If the file isn't valid JSON
    """
    with open(path) as f:
        return json.load(f)
