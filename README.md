# intellipat-mcp: Claude Code plugin

Submit and track IntelliPat patent **novelty** and **invalidity** searches from inside Claude Code.

> **Server address:** until `https://mcp.intellipat.ai/` is live, set `INTELLIPAT_MCP_URL` to the server address you were given with your API key (see [Configure](#configure)).

The plugin registers the IntelliPat MCP server as the `intellipat` MCP server and adds three skills on top of its tools. It also adds a session-start reminder for searches still in progress.

---

## Install

In Claude Code:

```
/plugin marketplace add https://github.com/IntelliPat-ai/intellipat-mcp.git
/plugin install intellipat-mcp@intellipat
```

`intellipat` is this repository's marketplace name. From a shell, the equivalents are `claude plugin marketplace add https://github.com/IntelliPat-ai/intellipat-mcp.git` and `claude plugin install intellipat-mcp@intellipat`.

The short form `/plugin marketplace add IntelliPat-ai/intellipat-mcp` also works, but it clones over SSH, so it needs a GitHub SSH key; the HTTPS URL above works without one.

## Configure

Set your API key in the environment Claude Code starts from (for example in `~/.bashrc` or `~/.zshrc`):

```bash
export INTELLIPAT_MCP_API_KEY="ip_..."
```

Create a key at <https://console.intellipat.ai> (API keys page), then restart Claude Code. The key is read **only** from this environment variable and sent as the `X-Api-Key` header. It is never written to a file by the plugin.

The server address defaults to **`https://mcp.intellipat.ai/`**. To point the plugin elsewhere, for example a staging server, set:

```bash
export INTELLIPAT_MCP_URL="https://your-server.example/"
```

Check the connection with `/mcp` in Claude Code: the `intellipat` server should be listed as connected.

---

## Skills

| Command | What it does |
|---|---|
| `/intellipat-mcp:submit-patent-search` | Shows your balance, collects the search inputs (proposing the claim's primary features for you to confirm), submits, records the job in project memory, and offers to check on it periodically. |
| `/intellipat-mcp:check-job-status [job_id] [--full]` | Checks one job. When it is done, shows the summary (and the full report with `--full`). |
| `/intellipat-mcp:review-pending-jobs` | Checks every pending job in this project in parallel and summarises the ones that finished. |

Claude Code loads plugin skills under the plugin's name (`/intellipat-mcp:<skill>`); the skills' own text uses the short names.

At the start of a session, the hook prints a one-line reminder if this project has searches in progress. It only reads a local file and makes no network calls.

---

## How searches are charged

- **Nothing is charged when you submit.** `submit_search` returns `credits_charged_micros: 0` and **`quoted_micros`**, the quote for the search at the tier you chose. You need at least the quote in available credits to submit.
- **The charge lands after the search completes:** its measured cost, **never more than twice the quote**. **A search that fails is not charged.**
- Prices are in credits; `1 credit = 1,000,000 micros`. With the current price book a `standard` search quotes **360 credits** (`screen` 144, `deep` 756). Always rely on the `quoted_micros` the server returns.
- Every submission carries a client-generated `idempotency_key`, so retrying the same submission returns the original job instead of starting a second one.

A real search usually takes **about 1.5–2.5 hours**.


---

## The `intellipat` MCP tools

The skills call these tools. You can also call them directly.

| Tool | Result |
|---|---|
| `get_credits` | `balance_micros` (int), `balance_usd`, `auto_reload_enabled`, `auto_reload_threshold_micros`, `auto_reload_amount_micros`. The auto-reload fields are shown for information only; they do not admit a search. |
| `submit_search` | Success: `{job_id, status: "pending", credits_charged_micros: 0, quoted_micros}`. A replayed retry may add `message`. `job_id` is 32-character hex when derived from `idempotency_key`, 20 characters otherwise; accept both. |
| `get_job_status` | `{job_id, status, created_at, updated_at, error, error_class}`. `status` is `pending` / `processing` / `done` / `error`. For a failed job, `error` is a customer-safe message ending `(reference <job_id>)` and `error_class` is `input_rejected` or `internal`; both are null otherwise. A job can be in `error`, with or without a message, while the service is still retrying it: re-check later, do not resubmit, and treat the failure as final only if the job still reads `error` at least 30 minutes after it was first seen. Older servers return the raw failure text and no `error_class`. |
| `get_report_summary` | `{job_id, status, title_matter, search_type, novelty_score, invalidity_score, report_summary, prior_art_count, prior_art_top}`. |
| `get_report` | `{job_id, status, created_at, updated_at, metadata}`: the full report. |

**`submit_search` arguments:**
- `title_matter`, `search_type` (`novelty`, the default, or `invalidity`), `claim_text`;
- **`primary_features`**: a non-empty list of non-empty strings, **required for a novelty search**. The service does not derive features from `claim_text`. Give the claim's main features, usually 4–7 (3–8 works well). At least one is required; there is no fixed maximum. More features make a search take longer; the quoted price is set by the tier, not the feature count.
- optionally `secondary_features`, `claims` (invalidity), `before_date` (`YYYY-MM-DD`), `tier` (`screen` / `standard` / `deep`) and `idempotency_key` (1–128 characters).

**Refusals** (an error result; nothing started, nothing charged):

| Code | Cause |
|---|---|
| `invalid_features` | Novelty search without usable `primary_features`. |
| `invalid_before_date` | `before_date` is not a real `YYYY-MM-DD` date. |
| `invalid_tier` | `tier` is not `screen`, `standard` or `deep`. |
| `invalid_idempotency_key` | The key is not a 1–128 character string. |
| `insufficient_credits` | Not enough available credits for the quote. |
| `quote_unavailable` | The search could not be priced right now. |
| `enqueue_failed` | The search could not be queued. |

A missing or invalid key is an authentication error.

---

## Project memory

The skills keep a record of your searches at:

```
$HOME/.claude/projects/<project-key>/memory/intellipat_jobs.md
```

`<project-key>` is the absolute project path with `/` replaced by `-` (leading dash removed). One block per job:

```markdown
## <job_id>
- title_matter: LiDAR pre-filter for autonomous vehicles
- search_type: novelty
- status: pending
- submitted_at: 2026-11-17T14:30:00Z
- quoted_credits: 360
- tier: standard
- idempotency_key: 6f1c2b9e-…
- project_context: Considering a freedom-to-operate filing on the LiDAR module
- last_checked_at: 2026-11-17T14:30:00Z
```

Status values: `pending`, `processing`, `done`, `error`, `unknown`. The session-start hook reads the `status:` lines.

---

## Files

```
intellipat-mcp/
├── .claude-plugin/
│   ├── plugin.json         # plugin manifest
│   └── marketplace.json    # makes this repo installable as the "intellipat" marketplace
├── .mcp.json               # the intellipat MCP server (URL default + API-key header from the environment)
├── skills/
│   ├── submit-patent-search/SKILL.md
│   ├── check-job-status/SKILL.md
│   └── review-pending-jobs/SKILL.md
├── hooks/
│   ├── hooks.json          # SessionStart hook registration
│   └── session-start.sh    # pending-search reminder (local file read only)
└── tests/check-contract.sh # checks the layout and the skill text against the server contract
```

For local development, run Claude Code with `claude --plugin-dir /path/to/intellipat-mcp`.
