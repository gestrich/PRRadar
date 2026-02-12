#!/usr/bin/env python3
"""Minimal Claude Agent SDK wrapper for Swift.

Accepts a JSON request on stdin and streams JSON-lines to stdout.
This is the only Python code required at runtime — everything else is Swift.

Input (stdin JSON):
    {
        "prompt": "...",
        "model": "claude-sonnet-4-20250514",
        "tools": ["Read", "Grep", "Glob"],  // optional
        "cwd": "/path/to/repo",             // optional
        "output_schema": { ... }             // optional JSON schema
    }

Output (stdout JSON-lines):
    {"type": "text", "content": "..."}
    {"type": "tool_use", "name": "Read", "input": {...}}
    {"type": "result", "output": {...}, "cost_usd": 0.05, "duration_ms": 1234}
"""

import asyncio
import json
import sys

from claude_agent_sdk import AssistantMessage, ClaudeAgentOptions, ResultMessage, query
from claude_agent_sdk.types import TextBlock, ToolUseBlock


def emit(obj: dict) -> None:
    print(json.dumps(obj, ensure_ascii=False), flush=True)


async def run(request: dict) -> None:
    prompt = request["prompt"]
    model = request.get("model", "claude-sonnet-4-20250514")
    tools = request.get("tools")
    cwd = request.get("cwd")
    output_schema = request.get("output_schema")

    options = ClaudeAgentOptions(model=model)

    if tools:
        options.allowed_tools = tools
    if cwd:
        options.cwd = cwd
    if output_schema:
        options.output_format = {"type": "json_schema", "schema": output_schema}

    async for message in query(prompt=prompt, options=options):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    emit({"type": "text", "content": block.text})
                elif isinstance(block, ToolUseBlock):
                    emit({
                        "type": "tool_use",
                        "name": block.name,
                        "input": block.input if hasattr(block, "input") else {},
                    })
        elif isinstance(message, ResultMessage):
            result: dict = {"type": "result"}
            if message.structured_output:
                result["output"] = message.structured_output
            if message.duration_ms:
                result["duration_ms"] = message.duration_ms
            if message.total_cost_usd:
                result["cost_usd"] = message.total_cost_usd
            emit(result)


def main() -> None:
    raw = sys.stdin.read()
    if not raw.strip():
        print(json.dumps({"type": "error", "message": "Empty input"}), file=sys.stderr)
        sys.exit(1)

    try:
        request = json.loads(raw)
    except json.JSONDecodeError as e:
        print(json.dumps({"type": "error", "message": str(e)}), file=sys.stderr)
        sys.exit(1)

    if "prompt" not in request:
        print(
            json.dumps({"type": "error", "message": "Missing required field: prompt"}),
            file=sys.stderr,
        )
        sys.exit(1)

    asyncio.run(run(request))


if __name__ == "__main__":
    main()
