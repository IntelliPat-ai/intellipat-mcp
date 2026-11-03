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

- If the user passed an argument (`/check-job-status <job_id>`), use it directly. A job id is either a **32-character hex** string (submitted with an `idempotency_key`) or a **20-character** id (submitted without one); accept both and never reject an id for its length.
- Otherwise, read `$HOME/.claude/projects/<project-key>/memory/intellipat_jobs.md`, list every job with `status: pending` or `status: processing`, and ask the user which one (or "all" → defer to `/review-pending-jobs`).
- If memory is empty / no pending jobs, tell the user "No active jobs in memory. Pass a job_id explicitly or run /submit-patent-search."

## Step 3 — Call get_job_status

```bash
curl -s -X POST "$INTELLIPAT_MCP_URL" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $INTELLIPAT_MCP_API_KEY" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"tools/call\",\"params\":{\"name\":\"get_job_status\",\"arguments\":{\"job_id\":\"$JOB_ID\"}}}"
```

**Reading any response.** Every call returns JSON-RPC. On success the tool's data is in `result.structuredContent` (the same JSON is in `result.content[0].text`). Check `result.isError` first: when `true`, the failure is described by `structuredContent` (e.g. `{"error": "insufficient_credits", ...}`) or, for not-found / not-yours, by the text in `content[0].text`. A top-level `error` (not `result`) is a protocol/auth failure — HTTP 401 means the key is missing, invalid or revoked (`error.data.code` is `no_credentials` or `invalid_api_key`).

`result.structuredContent` is `{job_id, status, created_at, updated_at, error}`; `error` is the failure message (or null). Expected `status` values: `pending`, `processing`, `done`, `error` — compare **case-insensitively** as a defensive rule (server builds from before the status-enum fix returned `PENDING`).

## Step 4 — Branch on status

### Status: `done`

1. Call `get_report_summary` (same response rules; its `structuredContent` is `{job_id, status, title_matter, search_type, novelty_score, invalidity_score, report_summary, prior_art_count, prior_art_top}`):
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
   - `result_summary: <one-line summary, e.g. "novelty_score: 72; 5 prior art references">`
3. Display a formatted summary to the user. For novelty/invalidity, show:
   - `novelty_score` (and `invalidity_score` when present; both may be null)
   - `prior_art_count`, and the `prior_art_top` references (up to 5) — each item is passed through exactly as stored, so show whatever title / number / date fields it has rather than assuming a schema
   - `report_summary` text if present
   For sanitized searches, show `prior_art_count` and the first few patent numbers in `prior_art_top`.
4. Offer the full report: "Want the full report? Run `/check-job-status <job_id> --full` or I can fetch it now (y/n)." If yes, call `get_report` and write it to `./<job_id>_report.json` (or print inline if small).

### Status: `error`

1. Update memory:
   - `status: error`
   - `last_checked_at: <now>`
   - `error_message: <structuredContent.error from get_job_status>`
2. Show the error and suggest opening a support ticket if the cause is non-obvious.

### Status: missing or unrecognised

If `status` is `null`, absent, or none of `pending` / `processing` / `done` / `error` (after lower-casing) — live dev data contains rows with no status and rows written by other tools in other casings — treat it as **`unknown`**: do **not** infer done or error, do not change the stored `status:` in memory (only `last_checked_at`), tell the user "the server reported no usable status for this job", and suggest checking again later or contacting support if it persists.

### Status: `pending` or `processing`

1. Update only `last_checked_at: <now>` in memory.
2. Compute elapsed time from `submitted_at` and display: "Job `<job_id>` is still **<status>** — submitted <elapsed> ago."
3. Suggest checking again later or running `/review-pending-jobs` for a batch view.

## Memory update mechanics

When updating a job entry in `intellipat_jobs.md`, edit in place — find the `## <job_id>` heading, locate the matching `- key:` line under it, and replace it. Add new keys (like `completed_at`, `result_summary`) as new lines under the same heading. Do not duplicate keys.

## Error handling

- Top-level JSON-RPC `error` / HTTP non-200 (401 = bad key; 404 `Method not found: tools/call` = pre-protocol server): surface the message verbatim. Do not modify memory.
- `result.isError` with text `Job … not found` or `Job … not owned by caller`: set the job's stored `status:` to `unknown` **and tell the user, in one line, that it is being dropped from the active list**. One exception: a job submitted within the last 10 minutes whose memory row has an `idempotency_key` may still be being created (its `submit_search` reply said so in a `message`) — for such a row say "not found yet", leave `status:` unchanged, update only `last_checked_at`, and only after 10 minutes of consecutive not-found answers apply the rule above and tell the user to resubmit with a **new** key (`/submit-patent-search`). Otherwise the rule stands (only `pending` / `processing` jobs are active, so it will no longer be offered above, re-checked by `/review-pending-jobs`, or counted by the session-start reminder). This is deliberately the opposite of a missing or unrecognised status: here the answer is definite (the job does not exist, or is not yours), so re-checking would only repeat it. The memory row is kept for reference, and `/check-job-status <job_id>` with an explicit id still reaches it.
