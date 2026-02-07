"""Domain models for GitHub API responses.

These models mirror GitHub's JSON structure exactly, providing type-safe
access to PR, repository, and comment data.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class GitHubAuthor:
    """GitHub user/author information."""

    login: str
    id: str = ""
    name: str = ""
    is_bot: bool = False

    @classmethod
    def from_dict(cls, data: dict) -> GitHubAuthor:
        return cls(
            login=data.get("login", ""),
            id=data.get("id", ""),
            name=data.get("name", ""),
            is_bot=data.get("is_bot", False),
        )


@dataclass
class GitHubLabel:
    """GitHub label."""

    id: str
    name: str
    description: str = ""
    color: str = ""

    @classmethod
    def from_dict(cls, data: dict) -> GitHubLabel:
        return cls(
            id=data.get("id", ""),
            name=data.get("name", ""),
            description=data.get("description", ""),
            color=data.get("color", ""),
        )


@dataclass
class GitHubFile:
    """File changed in a PR."""

    path: str
    additions: int = 0
    deletions: int = 0

    @classmethod
    def from_dict(cls, data: dict) -> GitHubFile:
        return cls(
            path=data.get("path", ""),
            additions=data.get("additions", 0),
            deletions=data.get("deletions", 0),
        )


@dataclass
class GitHubCommit:
    """Commit in a PR."""

    oid: str
    message_headline: str = ""
    message_body: str = ""
    authored_date: str = ""
    committed_date: str = ""

    @classmethod
    def from_dict(cls, data: dict) -> GitHubCommit:
        return cls(
            oid=data.get("oid", ""),
            message_headline=data.get("messageHeadline", ""),
            message_body=data.get("messageBody", ""),
            authored_date=data.get("authoredDate", ""),
            committed_date=data.get("committedDate", ""),
        )


@dataclass
class GitHubComment:
    """Comment on a PR."""

    id: str
    body: str
    author: GitHubAuthor | None = None
    created_at: str = ""
    url: str = ""

    @classmethod
    def from_dict(cls, data: dict) -> GitHubComment:
        author_data = data.get("author")
        return cls(
            id=data.get("id", ""),
            body=data.get("body", ""),
            author=GitHubAuthor.from_dict(author_data) if author_data else None,
            created_at=data.get("createdAt", ""),
            url=data.get("url", ""),
        )


@dataclass
class GitHubReview:
    """Review on a PR."""

    id: str
    body: str
    state: str = ""
    author: GitHubAuthor | None = None
    submitted_at: str = ""

    @classmethod
    def from_dict(cls, data: dict) -> GitHubReview:
        author_data = data.get("author")
        return cls(
            id=data.get("id", ""),
            body=data.get("body", ""),
            state=data.get("state", ""),
            author=GitHubAuthor.from_dict(author_data) if author_data else None,
            submitted_at=data.get("submittedAt", ""),
        )


@dataclass
class PullRequest:
    """GitHub Pull Request metadata."""

    number: int
    title: str
    body: str = ""
    state: str = ""
    is_draft: bool = False
    url: str = ""
    base_ref_name: str = ""
    head_ref_name: str = ""
    additions: int = 0
    deletions: int = 0
    changed_files: int = 0
    created_at: str = ""
    updated_at: str = ""
    author: GitHubAuthor | None = None
    labels: list[GitHubLabel] = field(default_factory=list)
    files: list[GitHubFile] = field(default_factory=list)
    commits: list[GitHubCommit] = field(default_factory=list)
    _raw_json: str = ""

    @classmethod
    def from_dict(cls, data: dict) -> PullRequest:
        author_data = data.get("author")
        return cls(
            number=data.get("number", 0),
            title=data.get("title", ""),
            body=data.get("body", ""),
            state=data.get("state", ""),
            is_draft=data.get("isDraft", False),
            url=data.get("url", ""),
            base_ref_name=data.get("baseRefName", ""),
            head_ref_name=data.get("headRefName", ""),
            additions=data.get("additions", 0),
            deletions=data.get("deletions", 0),
            changed_files=data.get("changedFiles", 0),
            created_at=data.get("createdAt", ""),
            updated_at=data.get("updatedAt", ""),
            author=GitHubAuthor.from_dict(author_data) if author_data else None,
            labels=[GitHubLabel.from_dict(l) for l in data.get("labels", [])],
            files=[GitHubFile.from_dict(f) for f in data.get("files", [])],
            commits=[GitHubCommit.from_dict(c) for c in data.get("commits", [])],
            _raw_json=json.dumps(data, indent=2),
        )

    @classmethod
    def from_json(cls, json_str: str) -> PullRequest:
        data = json.loads(json_str)
        pr = cls.from_dict(data)
        pr._raw_json = json_str
        return pr

    @classmethod
    def from_file(cls, path: Path) -> PullRequest:
        return cls.from_json(path.read_text())

    @property
    def raw_json(self) -> str:
        return self._raw_json


@dataclass
class PullRequestComments:
    """Comments and reviews on a PR."""

    comments: list[GitHubComment] = field(default_factory=list)
    reviews: list[GitHubReview] = field(default_factory=list)
    _raw_json: str = ""

    @classmethod
    def from_dict(cls, data: dict) -> PullRequestComments:
        return cls(
            comments=[GitHubComment.from_dict(c) for c in data.get("comments", [])],
            reviews=[GitHubReview.from_dict(r) for r in data.get("reviews", [])],
            _raw_json=json.dumps(data, indent=2),
        )

    @classmethod
    def from_json(cls, json_str: str) -> PullRequestComments:
        data = json.loads(json_str)
        comments = cls.from_dict(data)
        comments._raw_json = json_str
        return comments

    @classmethod
    def from_file(cls, path: Path) -> PullRequestComments:
        return cls.from_json(path.read_text())

    @property
    def raw_json(self) -> str:
        return self._raw_json


@dataclass
class GitHubOwner:
    """Repository owner."""

    login: str
    id: str = ""

    @classmethod
    def from_dict(cls, data: dict) -> GitHubOwner:
        return cls(
            login=data.get("login", ""),
            id=data.get("id", ""),
        )


@dataclass
class Repository:
    """GitHub Repository metadata."""

    name: str
    url: str = ""
    default_branch: str = ""
    owner: GitHubOwner | None = None
    _raw_json: str = ""

    @classmethod
    def from_dict(cls, data: dict) -> Repository:
        owner_data = data.get("owner")
        default_branch_ref = data.get("defaultBranchRef", {})
        return cls(
            name=data.get("name", ""),
            url=data.get("url", ""),
            default_branch=default_branch_ref.get("name", "") if default_branch_ref else "",
            owner=GitHubOwner.from_dict(owner_data) if owner_data else None,
            _raw_json=json.dumps(data, indent=2),
        )

    @classmethod
    def from_json(cls, json_str: str) -> Repository:
        data = json.loads(json_str)
        repo = cls.from_dict(data)
        repo._raw_json = json_str
        return repo

    @classmethod
    def from_file(cls, path: Path) -> Repository:
        return cls.from_json(path.read_text())

    @property
    def raw_json(self) -> str:
        return self._raw_json

    @property
    def full_name(self) -> str:
        if self.owner:
            return f"{self.owner.login}/{self.name}"
        return self.name
