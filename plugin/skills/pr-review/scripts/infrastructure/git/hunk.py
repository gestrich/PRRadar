import os
import re
from dataclasses import dataclass
from typing import List, Optional


@dataclass
class Hunk:
    """Represents a single hunk from a git diff."""
    file_path: str
    content: str
    raw_header: List[str]
    old_start: int = 0
    old_length: int = 0
    new_start: int = 0
    new_length: int = 0

    @property
    def chunk_name(self) -> str:
        """Generate a unique name for this hunk."""
        safe_name = self.file_path.replace('/', '_')
        return f"{safe_name}_L{self.new_start}"

    @property
    def filename(self) -> str:
        """Extract the filename from the file path."""
        return os.path.basename(self.file_path)

    def file_extension(self) -> str:
        """Extract the file extension from the file path without extension."""
        _, ext = os.path.splitext(self.file_path)
        return ext.lstrip('.')

    @staticmethod
    def from_hunk_data(file_header: List[str], hunk_lines: List[str], file_path: Optional[str]) -> "Hunk":
        """Create and add a new Hunk object."""
        if not file_path:
            return

        old_start = old_length = new_start = new_length = 0
        for line in hunk_lines:
            if line.startswith('@@'):
                match = re.match(r'^@@ -(\d+),(\d+) \+(\d+),(\d+) @@', line)
                if match:
                    old_start = int(match.group(1))
                    old_length = int(match.group(2))
                    new_start = int(match.group(3))
                    new_length = int(match.group(4))
                    break

        return Hunk(
            file_path=file_path,
            content="\n".join(file_header + hunk_lines),
            raw_header=file_header,
            old_start=old_start,
            old_length=old_length,
            new_start=new_start,
            new_length=new_length
        )
