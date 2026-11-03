---
name: submit-patent-search
description: Submit a new patent novelty, invalidity, or sanitized search to the Intellipat MCP API. Use when the user runs /submit-patent-search or asks to start a new patent search.
trigger: /submit-patent-search
---

# Submit Patent Search

Submit a new patent search job to the Intellipat MCP service. A search is charged to your credit balance (currently **$1.00 USD** = 1,000,000 credit micros, a price configured server-side) and runs asynchronously — typical turnaround is 15–45 minutes.

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

Call `get_credits` and display balance in USD before collecting input. If the balance is below the expected cost (currently $1.00), warn the user and offer to stop.

**Reading any response.** Every call returns JSON-RPC. On success the tool's data is in `result.structuredContent` (the same JSON is in `result.content[0].text`). Check `result.isError` first: when `true`, the failure is described by `structuredContent` (e.g. `{"error": "insufficient_credits", ...}`) or, for not-found / not-yours, by the text in `content[0].text`. A top-level `error` (not `result`) is a protocol/auth failure — HTTP 401 means the key is missing, invalid or revoked (`error.data.code` is `no_credentials` or `invalid_api_key`).


```bash
curl -s -X POST "$INTELLIPAT_MCP_URL" \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: $INTELLIPAT_MCP_API_KEY" \
  -d '{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":"get_credits","arguments":{}}}'
```

Read `result.structuredContent.balance_usd` (and `balance_micros`, an integer). Auto-reload settings are in `auto_reload_enabled`, `auto_reload_threshold_micros`, `auto_reload_amount_micros`. (The MCP *response* has no `creditBalanceMicros` key — that is the name of the underlying Firestore field, which the server maps to `balance_micros`.)

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
| `claims` | Invalidity only: array of `{claim_text, primary_features, secondary_features}`, one per claim. |

(The server does not currently read `preamble` or `general_text`; do not collect them.)

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

On success `result.structuredContent` is `{"job_id": "<20-char nanoid>", "status": "pending", "credits_charged_micros": <int>}`. Compare statuses case-insensitively and store them lowercase in memory (a defensive rule: server builds from before the status-enum fix returned `PENDING`).

**A `job_id` means a job exists. It does not confirm the charge succeeded.** `credits_charged_micros` is the *configured price* the server echoes; it is present even when the charge itself failed, and as of the current server a failed charge is still reported as success. Tell the user the search was *submitted*, not that they were charged; record the price as "price reported", never as "amount charged".

If `result.isError` is `true` and `structuredContent.error` is `insufficient_credits`, **no job was created**: show `structuredContent.balance` and point the user to the credits page. Never call `submit_search` a second time to "try again" — see Error handling.

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
- credits_cost_usd: <credits_charged_micros / 1_000_000 — the price the server reported; NOT proof that a charge succeeded>
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

- Top-level JSON-RPC `error` / non-200 HTTP status: surface `error.message` verbatim. Do not save anything to memory.
- HTTP 401 (`error.data.code` = `no_credentials` / `invalid_api_key`): tell the user the API key is missing, invalid or revoked, point them to `https://app.intellipat.ai/settings/api-keys`.
- HTTP 404 `Method not found: tools/call`: the server is an older, pre-protocol deployment. Tell the user the Intellipat MCP server needs to be upgraded; do not retry.
- `isError` with `insufficient_credits`: show `structuredContent.balance`, point to `https://app.intellipat.ai/settings/credits`. Nothing was charged.
- 🔴 **Network failure, timeout, or any response you cannot read, on `submit_search`: the outcome is NOT determinable from the client. Do not retry, do not guess, and do not use the credit balance to decide.** Tell the user plainly that a job may or may not have been created, and may or may not have been charged. Why the client cannot find out:
  - there is **no tool to list jobs**, and the `job_id` is created by the server — after a lost response you never learn it, so the job (if any) cannot be looked up at all;
  - the **balance cannot settle it either**: it can stay unchanged while a job runs (the charge can fail or be delayed), and with auto-reload on it can be unchanged *or higher* after a successful charge.

  The one check a *human* has: the credits page's ledger lists MCP charges with the job id in the description. A matching recent entry means the charge happened; **no entry does not prove no job is running.**

  **Re-submit only if the user explicitly confirms, after you have told them that doing so may create a second job and a second charge.** Never as an automatic retry, and never offered as the default.

Never claim a job was submitted unless the response contains a `job_id`.
