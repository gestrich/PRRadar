---
description: Imports must be alphabetically ordered
category: style
focus_type: file
applies_to:
  file_patterns: ["*.swift", "*.m"]
grep:
  any: ["@import", "import "]
new_code_lines_only: true
violation_script: scripts/check-import-order.sh
---

# Import Order (Script Analysis)

This rule uses a script to check that import statements are in alphabetical order. It demonstrates the `violation_script` field for script-based analysis.

## Rule YAML Fields

- **`violation_script`**: Path to the script, relative to the repo root.
- The script receives three positional arguments: `FILE_PATH`, `START_LINE`, `END_LINE`.
- The working directory is set to the repo root.

## Script Contract

The script outputs tab-delimited violations to stdout (one per line):

```
LINE_NUMBER<TAB>CHARACTER_POSITION<TAB>SCORE[<TAB>COMMENT]
```

- `LINE_NUMBER`: Positive integer
- `CHARACTER_POSITION`: Non-negative integer (use `0` if not meaningful)
- `SCORE`: Integer 1-10
- `COMMENT`: Optional human-readable description

Exit codes:
- `0` = success (violations from stdout; empty stdout = no violations)
- Non-zero = error (stderr captured as error message)

## Example Script

```bash
#!/bin/bash
# scripts/check-import-order.sh
# Checks that @import statements are sorted alphabetically.

FILE="$1"
START="$2"
END="$3"

prev=""
line_num=0
while IFS= read -r line; do
    line_num=$((line_num + 1))
    if [ "$line_num" -lt "$START" ] || [ "$line_num" -gt "$END" ]; then
        continue
    fi
    if echo "$line" | grep -q '^@import \|^import '; then
        current=$(echo "$line" | sed 's/^@import //; s/^import //; s/;$//')
        if [ -n "$prev" ] && [ "$(printf '%s\n%s' "$prev" "$current" | sort | head -1)" != "$prev" ]; then
            printf '%d\t0\t5\t%s should come before %s\n' "$line_num" "$current" "$prev"
        fi
        prev="$current"
    fi
done < "$FILE"
```

## Notes

- A rule cannot have both `violation_script` and `violation_regex` set.
- Scripts are linters — they run against the file on disk, not the diff. PRRadar post-filters violations against changed lines.
- `new_code_lines_only: true` means only violations on newly added lines are kept.
