"""Domain models for Claude Agent SDK structured outputs.

These models define the JSON schemas used with the Claude Agent SDK's
output_format parameter to ensure consistent, parseable responses.

Parse-once pattern: SDK JSON responses are parsed into type-safe models
at the boundary using from_dict() factory methods.
"""

from __future__ import annotations

from dataclasses import dataclass


# ============================================================
# Rule Applicability
# ============================================================


@dataclass
class RuleApplicability:
    """Structured output for rule applicability determination.

    Used by the rules command to determine if a rule applies to
    a given code segment based on file type, content, and context.
    """

    applicable: bool
    reason: str
    confidence: float

    # --------------------------------------------------------
    # JSON Schema
    # --------------------------------------------------------

    @classmethod
    def json_schema(cls) -> dict:
        """Return JSON schema for Claude Agent SDK structured output."""
        return {
            "type": "object",
            "properties": {
                "applicable": {
                    "type": "boolean",
                    "description": "Whether the rule applies to this code segment",
                },
                "reason": {
                    "type": "string",
                    "description": "Explanation of why the rule does or does not apply",
                },
                "confidence": {
                    "type": "number",
                    "minimum": 0,
                    "maximum": 1,
                    "description": "Confidence level from 0.0 (uncertain) to 1.0 (certain)",
                },
            },
            "required": ["applicable", "reason", "confidence"],
        }

    # --------------------------------------------------------
    # Factory Methods
    # --------------------------------------------------------

    @classmethod
    def from_dict(cls, data: dict) -> RuleApplicability:
        """Parse rule applicability from SDK JSON response.

        Args:
            data: Parsed JSON dictionary from Claude Agent SDK response

        Returns:
            Typed RuleApplicability instance
        """
        return cls(
            applicable=data["applicable"],
            reason=data["reason"],
            confidence=data["confidence"],
        )

    # --------------------------------------------------------
    # Serialization
    # --------------------------------------------------------

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        return {
            "applicable": self.applicable,
            "reason": self.reason,
            "confidence": self.confidence,
        }


# ============================================================
# Rule Evaluation
# ============================================================


@dataclass
class RuleEvaluation:
    """Structured output for rule violation evaluation.

    Used by the evaluate command to assess whether code violates
    a specific rule and provide actionable feedback.
    """

    violates_rule: bool
    score: int
    explanation: str
    suggestion: str
    file_path: str
    line_number: int | None

    # --------------------------------------------------------
    # JSON Schema
    # --------------------------------------------------------

    @classmethod
    def json_schema(cls) -> dict:
        """Return JSON schema for Claude Agent SDK structured output."""
        return {
            "type": "object",
            "properties": {
                "violates_rule": {
                    "type": "boolean",
                    "description": "Whether the code violates the rule",
                },
                "score": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 10,
                    "description": "Severity score: 1-4 minor, 5-7 moderate, 8-10 severe",
                },
                "explanation": {
                    "type": "string",
                    "description": "Detailed explanation of the violation or compliance",
                },
                "suggestion": {
                    "type": "string",
                    "description": "Specific suggestion for fixing the violation, if any",
                },
                "file_path": {
                    "type": "string",
                    "description": "Path to the file containing the code",
                },
                "line_number": {
                    "type": ["integer", "null"],
                    "description": "Specific line number of the violation, if applicable",
                },
            },
            "required": ["violates_rule", "score", "explanation"],
        }

    # --------------------------------------------------------
    # Factory Methods
    # --------------------------------------------------------

    @classmethod
    def from_dict(cls, data: dict) -> RuleEvaluation:
        """Parse rule evaluation from SDK JSON response.

        Args:
            data: Parsed JSON dictionary from Claude Agent SDK response

        Returns:
            Typed RuleEvaluation instance
        """
        return cls(
            violates_rule=data["violates_rule"],
            score=data["score"],
            explanation=data["explanation"],
            suggestion=data.get("suggestion", ""),
            file_path=data.get("file_path", ""),
            line_number=data.get("line_number"),
        )

    # --------------------------------------------------------
    # Serialization
    # --------------------------------------------------------

    def to_dict(self) -> dict:
        """Convert to dictionary for JSON serialization."""
        result = {
            "violates_rule": self.violates_rule,
            "score": self.score,
            "explanation": self.explanation,
            "suggestion": self.suggestion,
            "file_path": self.file_path,
        }
        if self.line_number is not None:
            result["line_number"] = self.line_number
        return result

    # --------------------------------------------------------
    # Public API
    # --------------------------------------------------------

    @property
    def is_violation(self) -> bool:
        """Whether this evaluation qualifies as a reportable violation."""
        return self.violates_rule and self.score >= 5
