# intellipat-mcp — Claude Code Plugin

Submit and track Intellipat patent novelty / invalidity / sanitized searches from inside any Claude Code session.

This plugin talks to the **Intellipat MCP Lambda** (`intellipat_mcp` package) via MCP `tools/call` (JSON-RPC 2.0 over HTTP) on an AWS Lambda Function URL, authenticated with a per-user API key. A search is charged to your credit balance — currently **$1.00 USD** (1,000,000 credit micros), a price configured server-side. The server charges **before** it creates the job: a success result means a job exists and was charged the amount in `credits_charged_micros`; an `isError` result means no search was started (or, for `enqueue_failed`, that the charge was refunded). Every submission carries a client-generated `idempotency_key`, so retrying the same submission returns the original job instead of charging again.

> **Server requirement.** Needs an `intellipat_mcp` deployment that implements the MCP protocol (`intellipat_mcp` `dev` ≥ `c1388f9`); keyed retries and `credits_charged_micros` as the amount charged need `dev` ≥ `9ba4da1`, and the optional `tier` argument a later build — the skills read `tools/list` and only use what the server advertises. An older deployment answers `tools/call` with HTTP 404 `Method not found: tools/call`; the skills detect this and tell you to upgrade the server instead of retrying. **No host has driven this plugin against a deployed protocol-conformant server yet** — it is built to the contract as landed in that repo and unit-tested there with fakes only.

---

## Install

1. Clone this repo into your Claude Code plugins directory:
   ```bash
   git clone <this-repo-url> ~/.claude/plugins/intellipat-mcp
   ```
   (Or symlink it from wherever you keep it: `ln -s /path/to/intellipat-mcp ~/.claude/plugins/intellipat-mcp`.)

2. Make the session-start hook executable:
   ```bash
   chmod +x ~/.claude/plugins/intellipat-mcp/hooks/session-start.sh
   ```

3. Restart Claude Code so the plugin manifest is picked up.

---

## Configure

Set both env vars before launching Claude Code (e.g. in `~/.bashrc`, `~/.zshrc`, or a per-project `.envrc`):

```bash
export INTELLIPAT_MCP_URL="https://<your-lambda-url>.lambda-url.us-east-2.on.aws/"
export INTELLIPAT_MCP_API_KEY="ip_..."
```

Get an API key at <https://app.intellipat.ai/settings/api-keys>.
The plugin will refuse to make any network call until both vars are set.

---

## Commands

| Slash command | Skill | What it does |
|---|---|---|
| `/submit-patent-search` | `skills/submit-patent-search.md` | Collects search inputs, calls `submit_search`, saves the job to project memory, optionally schedules polling. |
| `/check-job-status [job_id]` | `skills/check-job-status.md` | Checks one job. Fetches a summary if done, updates memory. |
| `/review-pending-jobs` | `skills/review-pending-jobs.md` | Parallel status check across every pending/processing job in this project. |

The `sessionStart` hook prints a one-line reminder at the top of each session if any pending jobs exist in this project's memory.

---

## Project Memory Format

Active and historical jobs are stored at:

```
$HOME/.claude/projects/<project-key>/memory/intellipat_jobs.md
```

…where `<project-key>` is the absolute project path with `/` replaced by `-` (leading dash stripped). Format:

```markdown
# Intellipat Jobs

## abc123def456ghi78901
- title_matter: LiDAR pre-filter for autonomous vehicles
- search_type: novelty
- status: pending
- submitted_at: 2026-05-08T14:30:00Z
- credits_cost_usd: 1.00   # the amount charged for this job (credits_charged_micros / 1_000_000)
- tier: standard
- idempotency_key: 6f1c2b9e-…   # the key sent with submit_search; a retry with it returns this same job
- before_date: 2024-01-15
- project_context: Considering a freedom-to-operate filing on the LiDAR module
- last_checked_at: 2026-05-08T14:30:00Z

## xyz987...
- title_matter: ...
- status: done
- completed_at: 2026-05-08T15:42:11Z
- result_summary: novelty_score: 72; 5 prior art references
- ...
```

Status values: `pending`, `processing`, `done`, `error`, `unknown` (stored lowercase; compare case-insensitively as a defensive rule — server builds from before the status-enum fix returned `PENDING`).
The `status:` line format is load-bearing — the session-start hook greps for it.

---

## Example Workflow

```text
$ claude
[2 Intellipat job(s) in progress — run /review-pending-jobs to check status]

> /submit-patent-search
… plugin checks env vars, calls get_credits → balance: $43.00
… asks for title_matter, search_type, claim_text, before_date
… extracts primary_features from claim_text, asks user to confirm
… calls submit_search → job_id = "abc123…"
… appends to intellipat_jobs.md, status: pending
… "Poll every 30 minutes via CronCreate? (y/n)" → y → schedules /check-job-status

(later, in a new session:)
[1 Intellipat job(s) in progress — run /review-pending-jobs to check status]

> /review-pending-jobs
… parallel get_job_status for all pending jobs
… one transitioned to done → fetches get_report_summary inline
… updates memory, prints table + inline summary
```

---

## Underlying MCP Tools

The plugin invokes these tools on the Intellipat MCP Lambda with `{"jsonrpc":"2.0","id":"1","method":"tools/call","params":{"name":<tool>,"arguments":{...}}}` and an `X-Api-Key` header. The server is stateless; no `initialize` handshake is required before `tools/call`.

Results arrive as `result.structuredContent` (mirrored as JSON text in `result.content[0].text`) with `result.isError`. Fields below are the server's, verbatim:

| Tool | `structuredContent` |
|---|---|
| `get_credits` | `balance_micros` (int), `balance_usd`, `auto_reload_enabled`, `auto_reload_threshold_micros`, `auto_reload_amount_micros`. |
| `submit_search` | `{job_id, status: "pending", credits_charged_micros}` — `credits_charged_micros` is the amount actually charged, present only on success; a replayed retry may add `message`. `job_id` is 32-hex when derived from `idempotency_key`, 20 characters when no key was sent — accept both. With `isError: true`: `{error, ...}` where `error` ∈ `insufficient_credits` (`balance`), `invalid_idempotency_key`, `invalid_tier`, `charge_failed` (no job started), `enqueue_failed` (charged, refunded, job recorded as `error`). Arguments: the fields in the skill plus optional `idempotency_key` (1–128 chars) and `tier` (`screen` / `standard` / `deep`). |
| `get_job_status` | `{job_id, status, created_at, updated_at, error}` (`pending` / `processing` / `done` / `error`, case-insensitive). |
| `get_report_summary` | `{job_id, status, title_matter, search_type, novelty_score, invalidity_score, report_summary, prior_art_count, prior_art_top}` (`prior_art_top` ≤ 5 items, passed through as stored). |
| `get_report` | `{job_id, status, created_at, updated_at, metadata}` — full parsed report metadata. |

Errors: HTTP 401 (`error.data.code` `no_credentials` / `invalid_api_key`) for a missing/bad key; `isError` results with text `Job … not found` / `not owned by caller`; JSON-RPC `-32602` for bad arguments. **Retrying `submit_search`:** send one fresh UUID as `idempotency_key` per logical submission and, on a timeout or unreadable response, retry the identical request with the **same** key — the server returns the original job and charges once. If the job then stays *not found* for more than 10 minutes, resubmit with a **new** key. A different search (or a different `tier`) is a new submission and needs a new key. Against a server whose `tools/list` does not advertise `idempotency_key`, the skill falls back to requiring explicit human confirmation before any re-submit.

---

## Files

```
intellipat-mcp/
├── .claude/settings.json        # Plugin manifest (name, version, skills, hooks, env)
├── skills/
│   ├── submit-patent-search.md
│   ├── check-job-status.md
│   └── review-pending-jobs.md
├── hooks/
│   └── session-start.sh         # Read-only pending-job reminder, no network
└── README.md
```

No Python / Node deps — the plugin is pure Markdown skills + a shell hook. All MCP calls are made by Claude via `Bash`+`curl` as instructed by the skills.
