---
name: review-pending-jobs
description: Review status of all pending/processing Intellipat patent search jobs in this project. Use when the user runs /review-pending-jobs.
trigger: /review-pending-jobs
---

# Review Pending Jobs

Bulk-check the status of every active Intellipat search job recorded in this project's memory.

## Step 1 — Verify environment

Both `INTELLIPAT_MCP_URL` and `INTELLIPAT_MCP_API_KEY` must be set. If missing, print setup instructions and stop.

## Step 2 — Read memory

```bash
PROJECT_KEY=$(echo "$PWD" | sed 's|/|-|g' | sed 's|^-||')
MEMORY_FILE="$HOME/.claude/projects/$PROJECT_KEY/memory/intellipat_jobs.md"
```

Parse `intellipat_jobs.md`:
- Each job is a `## <job_id>` block followed by `- key: value` lines.
- Keep only jobs whose `status:` is `pending` or `processing`.

If none are found:
> No active jobs. Run /submit-patent-search to start one, or /check-job-status <job_id> to look up a specific finished job.

…and stop.

## Step 3 — Parallel get_job_status

Issue one `get_job_status` MCP call **per active job in parallel** (multiple Bash tool calls in a single response). Example payload per call:

```bash
curl -s -X POST "$INTELLIPAT_MCP_URL" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $INTELLIPAT_MCP_API_KEY" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"tools/call\",\"params\":{\"name\":\"get_job_status\",\"arguments\":{\"job_id\":\"$JOB_ID\"}}}"
```

## Step 4 — Update memory

For every job, set `last_checked_at: <now>`. For jobs whose status has changed since the previous memory record, also update `status:` and any new fields (`completed_at`, `error_message`).

## Step 5 — Display table

Render a compact table of all checked jobs:

| Job ID | Title | Type | Status | Submitted | Elapsed |
|---|---|---|---|---|---|
| abc123… | LiDAR pre-filter | novelty | processing | 2026-05-08 13:00 | 1h 32m |

Truncate `Job ID` to first 8 chars and append `…`.

## Step 6 — Inline summaries for newly done jobs

For every job that just transitioned to `done` in this run, also call `get_report_summary` (parallelisable) and append a short summary section under the table:

```
### abc123… — LiDAR pre-filter (novelty) — done
- noveltyScore: 68
- Top references:
  - US10000000 — "..." (2019-04-12)
  - US10111111 — "..." (2018-08-30)
- Run /check-job-status abc123… --full for the complete report.
```

For newly transitioned `error` jobs, show the error message instead of a summary.

## Notes

- This skill is read/update only — it never submits new searches.
- Skip jobs whose `status` was already `done` or `error` in memory; we only refresh active ones to avoid wasteful API calls.
- If the API returns "job not found" for a job present in memory, mark its status as `unknown` and surface a one-line warning.
