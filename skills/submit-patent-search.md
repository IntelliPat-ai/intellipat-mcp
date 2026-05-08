---
name: submit-patent-search
description: Submit a new patent novelty, invalidity, or sanitized search to the Intellipat MCP API. Use when the user runs /submit-patent-search or asks to start a new patent search.
trigger: /submit-patent-search
---

# Submit Patent Search

Submit a new patent search job to the Intellipat MCP service. A search costs **$1.00 USD** (1,000,000 credit micros) and runs asynchronously — typical turnaround is 15–45 minutes.

## Step 1 — Verify environment

Both env vars must be set before any MCP call:

```bash
[ -n "$INTELLIPAT_MCP_URL" ] && [ -n "$INTELLIPAT_MCP_API_KEY" ] && echo OK || echo MISSING
```

If missing, print this and **stop** (do not prompt for anything else):

```
Intellipat MCP plugin is not configured. Set these env vars (e.g. in ~/.bashrc or your shell profile):

  export INTELLIPAT_MCP_URL="https://<your-lambda-url>.lambda-url.us-east-2.on.aws/"
  export INTELLIPAT_MCP_API_KEY="ip_..."

Create an API key at https://app.intellipat.ai/settings/api-keys
Then restart your Claude Code session and re-run /submit-patent-search.
```

## Step 2 — Show credit balance

Call `get_credits` and display balance in USD before collecting input. If balance is below $1.00, warn the user and offer to stop.

```bash
curl -s -X POST "$INTELLIPAT_MCP_URL" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $INTELLIPAT_MCP_API_KEY" \
  -d '{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"get_credits","arguments":{}}}'
```

The response contains `creditBalanceMicros`. Convert: `usd = micros / 1_000_000`. Each search costs $1.00.

## Step 3 — Collect search inputs

Use AskUserQuestion (or plain prompts if multi-field) to collect all fields. Required fields:

| Field | Type | Notes |
|---|---|---|
| `title_matter` | string | Short human-readable title for the search. Used in memory and reports. |
| `search_type` | enum | One of `novelty`, `invalidity`, `sanitized`. |
| `claim_text` | string | The full claim text (independent claim recommended). For invalidity, this can be a single claim or the lead independent claim. |
| `before_date` | string | Priority date in `YYYY-MM-DD` format. Prior art must be before this date. |
| `primary_features` | string[] | List of key claim features to search on. **You should suggest these by extracting noun phrases / functional limitations from `claim_text`, then ask the user to confirm or edit.** Aim for 3–8 features. |

Optional fields:

| Field | Notes |
|---|---|
| `secondary_features` | Additional context features (default: empty). |
| `preamble` | Claim preamble (default: derived from `claim_text`). |
| `general_text` | Background description (default: empty). |

### Extracting primary features

When the user provides `claim_text`, parse it locally and propose a list of features. Example for a method claim:

> "A method comprising: receiving a request from a client; validating the request against a stored token; and returning a response."

Suggested features:
- receiving a request from a client
- validating the request against a stored token
- returning a response

Show the suggested list and ask: "Use these features, or edit the list?" Accept user edits before submitting.

## Step 4 — Submit the search

Call `submit_search` with the collected arguments:

```bash
curl -s -X POST "$INTELLIPAT_MCP_URL" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $INTELLIPAT_MCP_API_KEY" \
  -d "$(cat <<JSON
{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"submit_search","arguments":{
  "title_matter": "...",
  "search_type": "novelty",
  "claim_text": "...",
  "before_date": "2024-01-15",
  "primary_features": ["...", "..."]
}}}
JSON
)"
```

The response contains `job_id` (a 20-char nanoid) and a status of `pending`.

## Step 5 — Persist to project memory

Save the job to project memory at `intellipat_jobs.md`. Determine the project memory directory:

```bash
PROJECT_KEY=$(echo "$PWD" | sed 's|/|-|g' | sed 's|^-||')
MEMORY_DIR="$HOME/.claude/projects/$PROJECT_KEY/memory"
mkdir -p "$MEMORY_DIR"
MEMORY_FILE="$MEMORY_DIR/intellipat_jobs.md"
```

Append a job entry in this exact format (preserving the `- ` and `key: value` lines so the session-start hook can grep `status:`):

```markdown
## <job_id>
- title_matter: <title_matter>
- search_type: <novelty|invalidity|sanitized>
- status: pending
- submitted_at: <ISO 8601 UTC, e.g. 2026-05-08T14:30:00Z>
- credits_cost_usd: 1.00
- before_date: <YYYY-MM-DD>
- project_context: <one-line description of why this search was run, drawn from current conversation>
- last_checked_at: <same as submitted_at>
```

If `intellipat_jobs.md` does not exist, create it with a top-level header `# Intellipat Jobs` first, then append. Also add a one-line pointer in `MEMORY.md` if not already present:

```
- [intellipat_jobs.md](intellipat_jobs.md) — Active and historical Intellipat patent-search jobs (status, results, project context)
```

## Step 6 — Offer polling

After the job is saved, offer to start a recurring status check:

> Poll job `<job_id>` every 30 minutes via CronCreate? (y/n)

If yes, use `CronCreate` to schedule `/check-job-status <job_id>` every 1800 seconds. If no, tell the user they can run `/check-job-status <job_id>` or `/review-pending-jobs` manually.

## Error handling

- Non-200 HTTP status from the Lambda URL: surface the JSON-RPC `error.message` field. Do not save anything to memory.
- `auth_error`: tell the user the API key is invalid or revoked, point them to `https://app.intellipat.ai/settings/api-keys`.
- `insufficient_credits`: show current balance, point to `https://app.intellipat.ai/settings/credits`.
- Network/curl failure: report and offer to retry.

Never claim a job was submitted unless the response contains a `job_id`.
