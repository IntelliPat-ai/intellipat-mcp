#!/bin/bash
# Read-only session-start reminder. No network calls.
MEMORY_FILE="$HOME/.claude/projects/$(echo "$PWD" | sed 's|/|-|g' | sed 's|^-||')/memory/intellipat_jobs.md"
if [ -f "$MEMORY_FILE" ]; then
  PENDING=$(grep -c "status: pending\|status: processing" "$MEMORY_FILE" 2>/dev/null || echo 0)
  if [ "$PENDING" -gt 0 ]; then
    echo "[$PENDING Intellipat job(s) in progress — run /review-pending-jobs to check status]"
  fi
fi
