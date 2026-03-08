#!/usr/bin/env bash
# =============================================================================
# PRRadar Daily Review Script
# =============================================================================
#
# SETUP: Fill in --config with your saved configuration name (see:
#   swift run PRRadarMacCLI config list
# Then choose one of the scheduling options below.
#
# -----------------------------------------------------------------------------
# Option A — cron (simpler)
# -----------------------------------------------------------------------------
# Add to crontab with: crontab -e
#
#   30 5 * * * /path/to/repo/scripts/daily-review.sh >> /tmp/prradar-daily.log 2>&1
#
# Note: cron requires the machine to be awake at 5:30 AM. If it's asleep, the
# job is skipped until the next day.
#
# -----------------------------------------------------------------------------
# Option B — launchd (preferred on macOS)
# -----------------------------------------------------------------------------
# launchd wakes the machine to run the job even if it was asleep at 5:30 AM.
#
# 1. Save the plist below to ~/Library/LaunchAgents/com.prradar.daily-review.plist
#    (replace /path/to/repo with the absolute path to this repository)
#
# 2. Load it:
#      launchctl load ~/Library/LaunchAgents/com.prradar.daily-review.plist
#
# 3. To unload:
#      launchctl unload ~/Library/LaunchAgents/com.prradar.daily-review.plist
#
# Plist template:
# ---------------
# <?xml version="1.0" encoding="UTF-8"?>
# <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
#   "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
# <plist version="1.0">
# <dict>
#   <key>Label</key>
#   <string>com.prradar.daily-review</string>
#   <key>ProgramArguments</key>
#   <array>
#     <string>/path/to/repo/scripts/daily-review.sh</string>
#   </array>
#   <key>StartCalendarInterval</key>
#   <dict>
#     <key>Hour</key>
#     <integer>5</integer>
#     <key>Minute</key>
#     <integer>30</integer>
#   </dict>
#   <key>StandardOutPath</key>
#   <string>/tmp/prradar-daily.log</string>
#   <key>StandardErrorPath</key>
#   <string>/tmp/prradar-daily.log</string>
# </dict>
# </plist>
# =============================================================================

set -euo pipefail

LOOKBACK_HOURS=24
MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lookback-hours) LOOKBACK_HOURS="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI="$REPO_ROOT/PRRadarLibrary/.build/release/PRRadarMacCLI"

# Build if binary is missing or any source file is newer
if [ ! -f "$CLI" ] || [ -n "$(find "$REPO_ROOT/PRRadarLibrary/Sources" -newer "$CLI" -name '*.swift' -print -quit)" ]; then
  cd "$REPO_ROOT/PRRadarLibrary" && swift build -c release --quiet
fi

# Run the daily review
# Using --updated-lookback-hours: updatedSince is a superset of createdSince for open PRs,
# so a single run covers both new and active PRs.
MODE_ARGS=()
if [ -n "$MODE" ]; then
  MODE_ARGS+=(--mode "$MODE")
fi

set +e
"$CLI" run-all \
  --config "ios" \
  --updated-lookback-hours "$LOOKBACK_HOURS" \
  "${MODE_ARGS[@]}" \
  --state open
  # --comment   # uncomment to post comments automatically
EXIT_CODE=$?
set -e

# macOS notification
if [ $EXIT_CODE -eq 0 ]; then
  osascript -e 'display notification "Daily PR review complete" with title "PRRadar" sound name "Glass"'
else
  osascript -e 'display notification "Daily PR review failed (exit '"$EXIT_CODE"')" with title "PRRadar" sound name "Basso"'
fi

exit $EXIT_CODE
