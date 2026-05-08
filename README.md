# intellipat-mcp — Claude Code Plugin

Submit and track Intellipat patent novelty / invalidity / sanitized searches from inside any Claude Code session.

This plugin talks to the **Intellipat MCP Lambda** (`intellipat_mcp` package) via JSON-RPC 2.0 over an AWS Lambda Function URL, authenticated with a per-user API key. Each search costs **$1.00 USD** (1,000,000 credit micros).

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
- credits_cost_usd: 1.00
- before_date: 2024-01-15
- project_context: Considering a freedom-to-operate filing on the LiDAR module
- last_checked_at: 2026-05-08T14:30:00Z

## xyz987...
- title_matter: ...
- status: done
- completed_at: 2026-05-08T15:42:11Z
- result_summary: noveltyScore: 72; 5 prior art references
- ...
```

Status values: `pending`, `processing`, `done`, `error`, `unknown`.
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

The plugin invokes these tools on the Intellipat MCP Lambda (JSON-RPC 2.0, `X-Api-Key` header):

| Tool | Purpose |
|---|---|
| `get_credits` | Returns `creditBalanceMicros` for the API key's user. |
| `submit_search` | Creates a Firestore job doc and enqueues to the gateway SQS queue. Returns `job_id`. |
| `get_job_status` | Returns current status of a job (`pending` / `processing` / `done` / `error`). |
| `get_report_summary` | Returns `noveltyScore` and top prior-art references for a done job. |
| `get_report` | Returns the full report JSON for a done job. |

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
