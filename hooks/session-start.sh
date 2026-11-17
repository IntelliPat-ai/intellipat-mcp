#!/bin/bash
# Read-only session-start reminder. No network calls.
MEMORY_FILE="$HOME/.claude/projects/$(echo "$PWD" | sed 's|/|-|g' | sed 's|^-||')/memory/intellipat_jobs.md"
if [ -f "$MEMORY_FILE" ]; then
  # grep -c prints 0 AND exits 1 when nothing matches, so no `|| echo 0` (that would print "0\n0")
  PENDING=$(grep -c "status: pending\|status: processing" "$MEMORY_FILE" 2>/dev/null)
  PENDING=${PENDING:-0}
  if [ "$PENDING" -gt 0 ]; then
    echo "[$PENDING Intellipat job(s) in progress — run /intellipat-mcp:review-pending-jobs to check status]"
  fi
fi
