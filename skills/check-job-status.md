---
name: check-job-status
description: Check status of a single Intellipat patent search job. Use when the user runs /check-job-status, optionally with a job_id argument.
trigger: /check-job-status
---

# Check Job Status

Check the status of one Intellipat patent search job, fetch its summary if done, and update project memory.

## Step 1 — Verify environment

Both `INTELLIPAT_MCP_URL` and `INTELLIPAT_MCP_API_KEY` must be set. If either is missing, print the same setup instructions as `/submit-patent-search` and stop.

## Step 2 — Resolve job_id

- If the user passed an argument (`/check-job-status <job_id>`), use it directly.
- Otherwise, read `$HOME/.claude/projects/<project-key>/memory/intellipat_jobs.md`, list every job with `status: pending` or `status: processing`, and ask the user which one (or "all" → defer to `/review-pending-jobs`).
- If memory is empty / no pending jobs, tell the user "No active jobs in memory. Pass a job_id explicitly or run /submit-patent-search."

## Step 3 — Call get_job_status

```bash
curl -s -X POST "$INTELLIPAT_MCP_URL" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $INTELLIPAT_MCP_API_KEY" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"tools/call\",\"params\":{\"name\":\"get_job_status\",\"arguments\":{\"job_id\":\"$JOB_ID\"}}}"
```

Expected `status` values: `pending`, `processing`, `done`, `error`.

## Step 4 — Branch on status

### Status: `done`

1. Call `get_report_summary`:
   ```bash
   curl -s -X POST "$INTELLIPAT_MCP_URL" \
     -H "Content-Type: application/json" \
     -H "X-Api-Key: $INTELLIPAT_MCP_API_KEY" \
     -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"tools/call\",\"params\":{\"name\":\"get_report_summary\",\"arguments\":{\"job_id\":\"$JOB_ID\"}}}"
   ```
2. Update the job's entry in `intellipat_jobs.md`:
   - `status: done`
   - `last_checked_at: <now>`
   - `completed_at: <now>` (only set if not already present)
   - `result_summary: <one-line summary, e.g. "noveltyScore: 72; 5 prior art references">`
3. Display a formatted summary to the user. For novelty/invalidity, show:
   - `noveltyScore` (or `invalidityScore = 100 - noveltyScore`)
   - Top 3–5 prior-art references with titles and dates
   - `report_summary` text if present
   For sanitized searches, show the count and first few patent numbers.
4. Offer the full report: "Want the full report? Run `/check-job-status <job_id> --full` or I can fetch it now (y/n)." If yes, call `get_report` and write it to `./<job_id>_report.json` (or print inline if small).

### Status: `error`

1. Update memory:
   - `status: error`
   - `last_checked_at: <now>`
   - `error_message: <error string from response>`
2. Show the error and suggest opening a support ticket if the cause is non-obvious.

### Status: `pending` or `processing`

1. Update only `last_checked_at: <now>` in memory.
2. Compute elapsed time from `submitted_at` and display: "Job `<job_id>` is still **<status>** — submitted <elapsed> ago."
3. Suggest checking again later or running `/review-pending-jobs` for a batch view.

## Memory update mechanics

When updating a job entry in `intellipat_jobs.md`, edit in place — find the `## <job_id>` heading, locate the matching `- key:` line under it, and replace it. Add new keys (like `completed_at`, `result_summary`) as new lines under the same heading. Do not duplicate keys.

## Error handling

- HTTP non-200 / JSON-RPC `error`: surface the message verbatim. Do not modify memory.
- Job not found in API but present in memory: warn the user — the job may have been deleted or the API key may not own it.
