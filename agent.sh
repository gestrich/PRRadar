#!/bin/bash
# Convenience script for running PRRadar agent mode
# Usage: ./agent.sh diff 123
#        ./agent.sh analyze 456 --rules-dir ./my-rules

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$HOME/Desktop/code-reviews"
VENV_DIR="$SCRIPT_DIR/.venv"

# Source .env if it exists (for ANTHROPIC_API_KEY)
if [ -f "$SCRIPT_DIR/.env" ]; then
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | xargs)
fi

# Check for API key
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "Error: ANTHROPIC_API_KEY environment variable is not set"
    echo "Set it in your shell profile or create a .env file in the repo root"
    exit 1
fi

# Check for virtual environment
if [ ! -d "$VENV_DIR" ]; then
    echo "Error: Virtual environment not found at $VENV_DIR"
    echo "Create it with: python3.11 -m venv $VENV_DIR && $VENV_DIR/bin/pip install -r requirements.txt"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Set PYTHONPATH to include the scripts directory
export PYTHONPATH="$SCRIPT_DIR/plugin/skills/pr-review:$PYTHONPATH"

# Run the agent command with output dir and pass all arguments using venv Python
"$VENV_DIR/bin/python" -m scripts agent --output-dir "$OUTPUT_DIR" "$@"
