import re
from dataclasses import dataclass
from typing import List, Optional

from .hunk import Hunk


@dataclass
class GitDiff:
    """Represents a complete git diff with all its hunks."""
    raw_content: str
    hunks: List[Hunk]
    commit_hash: str

    @staticmethod
    def from_diff_content(diff_content: str, commit_hash: str) -> "GitDiff":
        """Parse the diff content into individual hunks."""
        lines = diff_content.split("\n")
        current_hunk = []
        file_header = []
        current_file = None
        in_hunk = False
        hunks = []

        i = 0
        while i < len(lines):
            line = lines[i]

            if line.startswith("diff --git"):
                # Example: diff --git a/PRRadar/analysis_request_source.py b/PRRadar/analysis_request_source.py
                if current_hunk:
                    hunks.append(Hunk.from_hunk_data(file_header, current_hunk, current_file))
                    current_hunk = []
                    file_header = []

                # Extract the current file name using regex to handle spaces in paths
                match = re.match(r'diff --git "?a/([^"]*)"? "?b/([^"]*)"?', line)
                if not match:
                    match = re.match(r'diff --git a/(.*?) b/(.*?)(?:similarity index|$)', line)

                if match:
                    current_file = match.group(2).strip()

                file_header = [line]
                in_hunk = False

            elif line.startswith("index "):
                # Example: index 42969a851de..8db0ae51d45 100644
                file_header.append(line)

            elif line.startswith("--- "):
                # Example: --- a/PRRadar/analysis_request_source.py
                file_header.append(line)

            elif line.startswith("+++ "):
                # Example: +++ b/PRRadar/analysis_request_source.py
                file_header.append(line)

            elif line.startswith("@@"):
                # Example: @@ -33,7 +33,7 @@ class AnalysisRequestSource:
                if current_hunk:
                    hunks.append(Hunk.from_hunk_data(file_header, current_hunk, current_file))
                    current_hunk = []
                in_hunk = True
                current_hunk.append(line)

            elif in_hunk:
                current_hunk.append(line)

            i += 1

        if current_hunk:
            hunks.append(Hunk.from_hunk_data(file_header, current_hunk, current_file))

        return GitDiff(raw_content=diff_content, hunks=hunks, commit_hash=commit_hash)

    @property
    def is_empty(self) -> bool:
        """Check if the diff is empty."""
        return not self.raw_content or not self.hunks

    def get_hunks_by_file_extensions(self, extensions: Optional[List[str]] = None) -> List[Hunk]:
        """Return the list of parsed hunks, optionally filtered by file extensions."""
        if extensions is None:
            return self.hunks
        return [hunk for hunk in self.hunks if hunk.file_extension() in extensions]

    def get_hunks_by_file_path(self, file_path: str) -> List[Hunk]:
        """Return all hunks that match the given file path."""
        return [hunk for hunk in self.hunks if hunk.file_path == file_path]
