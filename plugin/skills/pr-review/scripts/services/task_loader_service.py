"""Task loader service - load evaluation tasks from filesystem.

Core service following the Service Layer pattern. Single responsibility:
parse and load evaluation tasks from JSON files.

Constructor injection pattern - dependency (tasks_dir) passed in, not created internally.
"""

from __future__ import annotations

import json
from pathlib import Path

from scripts.domain.evaluation_task import EvaluationTask


class TaskLoaderService:
    """Load evaluation tasks from JSON files.

    Core service - single responsibility, direct filesystem access.
    """

    def __init__(self, tasks_dir: Path):
        """Initialize with tasks directory.

        Args:
            tasks_dir: Directory containing task JSON files
        """
        self.tasks_dir = tasks_dir

    def load_all(self) -> list[EvaluationTask]:
        """Load all tasks from the tasks directory.

        Returns empty list if no tasks found (not exceptional).
        Raises exception on parse errors (abnormal case).

        Returns:
            List of all evaluation tasks, empty if none found
        """
        if not self.tasks_dir.exists():
            return []

        task_files = sorted(self.tasks_dir.glob("*.json"))
        if not task_files:
            return []

        tasks: list[EvaluationTask] = []
        for task_file in task_files:
            task = self._parse_task_file(task_file)
            if task is not None:
                tasks.append(task)

        # Sort by file path (alphabetic), then by line number within each file
        tasks.sort(key=lambda t: (t.segment.file_path, t.segment.start_line))

        return tasks

    def load_filtered(self, rules_filter: list[str]) -> list[EvaluationTask]:
        """Load tasks matching the specified rule names.

        Args:
            rules_filter: List of rule names to include

        Returns:
            List of tasks matching the filter, empty if none match
        """
        all_tasks = self.load_all()
        return [t for t in all_tasks if t.rule.name in rules_filter]

    @staticmethod
    def _parse_task_file(file_path: Path) -> EvaluationTask | None:
        """Parse a single task file.

        Static method - pure function, no state dependency.

        Args:
            file_path: Path to task JSON file

        Returns:
            Parsed EvaluationTask, or None if parsing failed
        """
        try:
            data = json.loads(file_path.read_text())
            return EvaluationTask.from_dict(data)
        except (json.JSONDecodeError, KeyError):
            return None
