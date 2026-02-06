import sys

import requests

from .git_diff import GitDiff
from .repo_source import GitRepoSource


class GithubRepo(GitRepoSource):
    """Implementation for GitHub repository operations."""

    def __init__(self, github_token: str, owner: str, repo: str):
        self.github_token = github_token
        self.owner = owner
        self.repo = repo
        self.headers = {
            'Authorization': f'token {github_token}',
            'Accept': 'application/vnd.github.v3.diff'
        }

    def get_commit_diff(self, commit_hash: str) -> GitDiff:
        try:
            url = f"https://api.github.com/repos/{self.owner}/{self.repo}/commits/{commit_hash}"
            response = requests.get(url, headers=self.headers)
            response.raise_for_status()

            git_diff = GitDiff.from_diff_content(response.text, commit_hash=commit_hash)
            return git_diff
        except requests.RequestException as e:
            print(f"Error fetching diff from GitHub: {e}", file=sys.stderr)
            sys.exit(1)

    def get_pull_request_diff(self, pr_number: int) -> GitDiff:
        try:
            # Get PR diff
            url = f"https://api.github.com/repos/{self.owner}/{self.repo}/pulls/{pr_number}"
            response = requests.get(url, headers=self.headers)
            response.raise_for_status()

            # Get PR details to get the head SHA
            pr_details_headers = {**self.headers, 'Accept': 'application/vnd.github.v3+json'}
            pr_details = requests.get(url, headers=pr_details_headers).json()
            head_sha = pr_details['head']['sha']

            git_diff = GitDiff.from_diff_content(response.text, commit_hash=head_sha)
            return git_diff
        except requests.RequestException as e:
            print(f"Error fetching PR diff from GitHub: {e}", file=sys.stderr)
            sys.exit(1)

    def get_compare_diff(self, base_branch: str, target_branch: str) -> GitDiff:
        """Get the diff between two branches/commits using GitHub compare API."""
        try:
            # Strip 'origin/' prefix for GitHub API - it only understands branch names
            clean_base = base_branch.replace('origin/', '') if base_branch.startswith('origin/') else base_branch
            clean_target = target_branch.replace('origin/', '') if target_branch.startswith('origin/') else target_branch

            # Use the compare API to get diff between branches
            url = f"https://api.github.com/repos/{self.owner}/{self.repo}/compare/{clean_base}...{clean_target}"
            response = requests.get(url, headers=self.headers)
            response.raise_for_status()

            git_diff = GitDiff.from_diff_content(response.text, commit_hash=target_branch)
            return git_diff
        except requests.RequestException as e:
            print(f"Error fetching branch diff from GitHub: {e}", file=sys.stderr)
            sys.exit(1)

    def get_file_content(self, file_path: str, commit_hash: str) -> str:
        try:
            headers = {**self.headers, 'Accept': 'application/vnd.github.v3.raw'}
            encoded_path = requests.utils.quote(file_path)
            url = f"https://api.github.com/repos/{self.owner}/{self.repo}/contents/{encoded_path}?ref={commit_hash}"

            response = requests.get(url, headers=headers)
            response.raise_for_status()
            if response.status_code == 200:
                return response.text
            return ""
        except requests.RequestException as e:
            print(f"Error fetching file content from GitHub: {e}", file=sys.stderr)
            return ""

    def get_pull_request_details(self, pr_number: int) -> dict:
        """Get pull request details including base and target commit information."""
        try:
            url = f"https://api.github.com/repos/{self.owner}/{self.repo}/pulls/{pr_number}"
            headers = {**self.headers, 'Accept': 'application/vnd.github.v3+json'}
            response = requests.get(url, headers=headers)
            response.raise_for_status()

            pr_data = response.json()
            return {
                'base_commit': pr_data['base']['sha'],
                'target_commit': pr_data['head']['sha'],
                'base_branch': pr_data['base']['ref'],
                'target_branch': pr_data['head']['ref'],
                'title': pr_data['title'],
                'number': pr_data['number']
            }
        except requests.RequestException as e:
            print(f"Error fetching PR details from GitHub: {e}", file=sys.stderr)
            sys.exit(1)

    def get_open_pull_requests(self) -> list:
        """Get all open pull requests with pagination support."""
        try:
            all_prs = []
            page = 1
            per_page = 100

            while True:
                url = f"https://api.github.com/repos/{self.owner}/{self.repo}/pulls"
                params = {
                    'state': 'open',
                    'page': page,
                    'per_page': per_page,
                    'sort': 'created',
                    'direction': 'desc'
                }
                headers = {**self.headers, 'Accept': 'application/vnd.github.v3+json'}

                response = requests.get(url, headers=headers, params=params)
                response.raise_for_status()

                prs = response.json()

                if not prs:
                    break

                page_prs = [
                    {
                        'number': pr['number'],
                        'title': pr['title'],
                        'base_commit': pr['base']['sha'],
                        'target_commit': pr['head']['sha'],
                        'base_branch': pr['base']['ref'],
                        'target_branch': pr['head']['ref'],
                        'state': pr['state'],
                        'created_at': pr['created_at'],
                        'updated_at': pr['updated_at']
                    }
                    for pr in prs if pr['state'] == 'open'
                ]

                all_prs.extend(page_prs)

                if len(prs) < per_page:
                    break

                page += 1

            all_prs.sort(key=lambda x: x['created_at'], reverse=True)

            return all_prs
        except requests.RequestException as e:
            print(f"Error fetching open PRs from GitHub: {e}", file=sys.stderr)
            sys.exit(1)
