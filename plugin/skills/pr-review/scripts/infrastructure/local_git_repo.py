import subprocess
import sys

from .git_diff import GitDiff
from .repo_source import GitRepoSource


class LocalGitRepo(GitRepoSource):
    """Implementation for local git repository operations."""

    def get_commit_diff(self, commit_hash: str) -> GitDiff:
        try:
            subprocess.run(['git', 'fetch', "origin", commit_hash],
                                  capture_output=True,
                                  text=True,
                                  check=True)
            # The  -U flag (ex -U20) doesn't work great as it joins hunks together which
            # is often not good for analysis.
            result = subprocess.run(['git', 'diff', f"{commit_hash}^", f"{commit_hash}"],
                                  capture_output=True,
                                  text=True,
                                  check=True)
            return GitDiff.from_diff_content(result.stdout, commit_hash=commit_hash)
        except subprocess.CalledProcessError as e:
            print(f"Error getting diff: {e}", file=sys.stderr)
            sys.exit(1)

    def get_file_content(self, file_path: str, commit_hash: str) -> str:
        try:
            subprocess.run(['git', 'fetch', "origin", commit_hash],
                                  capture_output=True,
                                  text=True,
                                  check=True)
            result = subprocess.run(['git', 'show', f'{commit_hash}:{file_path}'],
                                  capture_output=True,
                                  text=True,
                                  check=True)
            return result.stdout
        except subprocess.CalledProcessError as e:
            print(f"Error getting file content: {e}", file=sys.stderr)
            return ""
