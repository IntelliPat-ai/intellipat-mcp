---
name: review-pending-jobs
description: Check the status of every pending or processing IntelliPat patent search recorded in this project's memory, update memory, and summarise newly finished searches. Use when the user runs /review-pending-jobs.
---

# Review Pending Jobs

Check every active IntelliPat search job recorded in this project's memory, through the `intellipat` MCP server's tools.

## Step 1: Read memory

```bash
PROJECT_KEY=$(echo "$PWD" | sed 's|/|-|g' | sed 's|^-||')
MEMORY_FILE="$HOME/.claude/projects/$PROJECT_KEY/memory/intellipat_jobs.md"
```

Each job is a `## <job_id>` block followed by `- key: value` lines. Keep only jobs whose `status:` is `pending` or `processing`. Ids are **32-character hex** (submitted with an `idempotency_key`) or **20-character**; accept both.

If there are none:
> No active jobs. Run /submit-patent-search to start one, or /check-job-status <job_id> to look up a finished job.

…and stop.

## Step 2: Check all of them in parallel

Call **`get_job_status`** once per active job, **in parallel** (several tool calls in one response). Each result is `{job_id, status, created_at, updated_at, error, error_class}`; an error result applies to that job only. Compare `status` case-insensitively. If the first calls fail with an authentication error, stop the whole review and say once that `INTELLIPAT_MCP_API_KEY` must be set (see `/submit-patent-search`, Step 1).

## Step 3: Update memory

For every job, set `last_checked_at: <now>`. Apply the same rules as `/check-job-status`:
- `done`: `status: done`, `completed_at`.
- `error` with **`error` null**: failed or retrying, reason not available yet. Keep `status:` unchanged and re-check next time; never resubmit.
- `error` with an `error` message: record `error_message`, `error_class` and `first_error_at` (if absent); set `status: error` only if it still reads `error` at least 30 minutes after `first_error_at`. The service can retry after a failure message is recorded.
- unknown status: leave `status:` unchanged.
- not found / not yours: the 10-minute grace for keyed jobs, then `status: unknown`.

## Step 4: Show a table

| Job ID | Title | Type | Status | Submitted | Elapsed |
|---|---|---|---|---|---|
| abc12345… | LiDAR pre-filter | novelty | processing | 2026-11-17 13:00 | 1h 32m |

Truncate the job id to its first 8 characters and append `…` (the same for both id shapes). Show a job reading `error` with a null `error` as `failed or retrying`. A real search usually takes about 1.5–2.5 hours, so long `processing` times are normal.

## Step 5: Summaries for newly finished jobs

For every job that became `done` in this run, call **`get_report_summary`** (in parallel) and add a short section under the table:

```
### abc12345… — LiDAR pre-filter (novelty) — done
- novelty_score: 68
- Top references:
  - US10000000 — "..." (2019-04-12)
- Run /check-job-status abc12345… --full for the complete report.
```

For a job that failed in this run, show its `error` message (with its reference) and `error_class` instead.

## Notes

- This skill only reads and updates; it never submits a search.
- Jobs already `done` or `error` in memory are skipped, to avoid needless calls.
- A failed search is not charged; a finished search is charged after completion its measured cost, never more than twice its quote.
