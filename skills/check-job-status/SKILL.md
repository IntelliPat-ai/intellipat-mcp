---
name: check-job-status
description: Check the status of one IntelliPat patent search job, fetch its summary when it is done, and update project memory. Use when the user runs /check-job-status, optionally with a job id.
argument-hint: "[job_id] [--full]"
---

# Check Job Status

Check one IntelliPat search job through the `intellipat` MCP server's tools, fetch its summary if it is done, and update project memory.

## Step 1: Resolve the job id

- If the user passed an id (`/check-job-status <job_id>`), use it. An id is either a **32-character hex** string (submitted with an `idempotency_key`) or a **20-character** id; accept both and never reject an id for its length.
- Otherwise read `$HOME/.claude/projects/<project-key>/memory/intellipat_jobs.md` (`<project-key>` = the absolute project path with `/` replaced by `-`, leading dash removed). List the jobs with `status: pending` or `status: processing` and ask which one ("all" → run `/review-pending-jobs` instead).
- If there are none: "No active jobs in memory. Pass a job id or run /submit-patent-search."

## Step 2: Call `get_job_status`

Call **`get_job_status`** with `{"job_id": "<id>"}`. If the tool is unavailable or fails with an authentication error, tell the user to set `INTELLIPAT_MCP_API_KEY` (see `/submit-patent-search`, Step 1) and stop.

The result is `{job_id, status, created_at, updated_at, error, error_class}`:
- `status` is `pending`, `processing`, `done` or `error`. Compare case-insensitively.
- On a failure, `error` is a **customer-safe message that includes a reference** (the job id). Show it verbatim; the user quotes the reference when contacting support. Otherwise `error` is null.
- `error_class` is `input_rejected` (the search engine rejected the input), `internal` (a service-side failure), or null. Older servers omit it; treat absent as null.

## Step 3: Act on the status

### `done`

1. Call **`get_report_summary`** with the job id. The result is `{job_id, status, title_matter, search_type, novelty_score, invalidity_score, report_summary, prior_art_count, prior_art_top}`.
2. Update the job in `intellipat_jobs.md`:
   - set `status: done` and `last_checked_at: <now>`;
   - set `completed_at: <now>` if absent;
   - set `result_summary: <one line, e.g. "novelty_score: 72; 5 prior art references">`.
3. Show the user:
   - `novelty_score`, and `invalidity_score` when present (either may be null);
   - `prior_art_count` and the `prior_art_top` references (up to 5). Show the fields each item actually has; do not assume a schema;
   - `report_summary` if present.
4. Mention that the search is now charged its measured cost, **never more than twice the quote**, and that the charge is visible on the credits page.
5. Offer the full report: with `--full`, or if the user says yes, call **`get_report`** and write it to `./<job_id>_report.json` (or show it inline if small).

### `error`

A search can read `error` **while the service is still retrying it**: a later attempt can start minutes after a failure and may succeed. So:

1. Tell the user: "The search failed; it may be retried automatically. I will check again later." Show `error` (with its reference) and `error_class`.
2. Update memory: `last_checked_at: <now>`, `error_message: <error>`, `error_class: <error_class>`. Keep `status:` as it was (`pending` / `processing`) on the **first** `error` you see; set `status: error` only if the job still reads `error` on a check **at least 30 minutes later** (record `first_error_at: <now>` to time it).
3. Never resubmit because of a single `error`. A failed search is not charged.
4. For `input_rejected`, suggest reviewing the claim text and features before submitting a new search. For `internal`, suggest contacting support with the reference.

### `pending` or `processing`

1. Update only `last_checked_at: <now>`.
2. Show: "Job `<job_id>` is still **<status>**, submitted <elapsed> ago." A full search usually takes one to three hours.
3. Suggest checking again later, or `/review-pending-jobs` for all jobs.

### Missing or unrecognised status

If `status` is null, absent, or not one of the four values (after lower-casing), treat it as **unknown**. Do not infer done or error, and do not change the stored `status:` (only `last_checked_at`). Tell the user the service reported no usable status, and suggest checking again later or contacting support if it persists.

## Updating memory

Edit in place: find the `## <job_id>` heading, replace the matching `- key:` line under it, and add new keys as new lines under the same heading. Never duplicate a key.

## Error handling

- **Authentication errors:** the setup message above. Do not modify memory.
- **A not-found or not-yours result** (`Job … not found` / `not owned by caller`): set the stored `status:` to `unknown` and tell the user, in one line, that the job is leaving the active list. **Exception:** a job submitted less than 10 minutes ago whose memory row has an `idempotency_key` may still be being created. Say "not found yet", leave `status:` unchanged and update only `last_checked_at`. After 10 minutes of consecutive not-found answers, apply the rule and suggest resubmitting with a **new** key (`/submit-patent-search`). The row stays in memory, and `/check-job-status <job_id>` with an explicit id still reaches it.
