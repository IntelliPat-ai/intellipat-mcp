#!/bin/bash
# Contract check for the plugin. It is markdown, JSON and one hook, with no code to unit-test, so this
# asserts (1) the plugin uses Claude Code's documented layout and (2) every skill and the README teach
# the CURRENT server contract and no longer carry the statements that pre-dated it. One check per line.
# Run: bash tests/check-contract.sh   (exit 0 = all checks pass; prints pass/fail counts)
#
# What a pass means: the `must` patterns match the operative sentences (presence) and the `mustnt`
# patterns pin superseded statements (absence). A pass is not proof that the surrounding prose agrees,
# and not proof that Claude Code loads the plugin; for that, run `claude --plugin-dir .` (README).
set -u
cd "$(dirname "$0")/.."
PASS=0; FAIL=0
ok()     { PASS=$((PASS+1)); }
bad()    { FAIL=$((FAIL+1)); echo "FAIL  $1"; }
must()   { if grep -qE -- "$2" "$1"; then ok; else bad "$1 lacks: $2"; fi; }
mustnt() { if grep -qE -- "$2" "$1"; then bad "$1 still has: $2"; else ok; fi; }
json()   { if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$1" 2>/dev/null; then ok; else bad "$1 is not valid JSON"; fi; }
exists() { if [ -e "$1" ]; then ok; else bad "missing: $1"; fi; }
gone()   { if [ -e "$1" ]; then bad "should be gone: $1"; else ok; fi; }

S=skills/submit-patent-search/SKILL.md; C=skills/check-job-status/SKILL.md; R=skills/review-pending-jobs/SKILL.md; M=README.md
SKILLS="$S $C $R"

# -- 1. layout (documented plugin format)
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json .mcp.json hooks/hooks.json; do exists $f; json $f; done
for f in $SKILLS hooks/session-start.sh; do exists $f; done
exists LICENSE; must LICENSE '^MIT License$'; must LICENSE '^Copyright \(c\) 2026 IntelliPat$'; must .claude-plugin/plugin.json '"license": "MIT"'
gone .claude/settings.json; gone skills/submit-patent-search.md; gone skills/check-job-status.md; gone skills/review-pending-jobs.md
must .claude-plugin/plugin.json '"name": "intellipat-mcp"'
must .claude-plugin/marketplace.json '"name": "intellipat"'
must .claude-plugin/marketplace.json '"source": "\./"'
must .mcp.json '"url": "\$\{INTELLIPAT_MCP_URL:-https://mcp\.intellipat\.ai/\}"'
must .mcp.json '"X-Api-Key": "\$\{INTELLIPAT_MCP_API_KEY:-\}"'
must hooks/hooks.json '"SessionStart"'
must hooks/hooks.json '\$\{CLAUDE_PLUGIN_ROOT\}/hooks/session-start\.sh'
for f in $SKILLS; do
  if [ "$(head -1 "$f")" = "---" ]; then ok; else bad "$f has no frontmatter"; fi
  must $f '^name: [a-z-]+$'; must $f '^description: .+'
  mustnt $f '^trigger:'
done

# -- 2. the charge model: serve-then-charge
must $S 'Submitting a search charges nothing'
must $S '`credits_charged_micros` is `0` and `quoted_micros` carries the quote'
must $S 'never more than twice the quote'
must $S 'A search that fails is not charged'
must $M 'Nothing is charged when you submit'
must $M 'never more than twice the quote'
must $M 'standard` search quotes \*\*360 credits\*\*'
for f in $SKILLS $M; do
  mustnt $f 'charges your balance \*before\*|CHARGES credits|charged before|Charge-then-serve'
  mustnt $f 'refunded|charge_failed|amount actually charged|credits_cost_usd'
done

# -- 3. inputs and refusals
must $S '\*\*Required for a novelty search\.\*\*'
must $S 'Do not submit a novelty search until the user has confirmed a non-empty feature list'
must $M 'required for a novelty search'
for code in invalid_features invalid_before_date invalid_tier invalid_idempotency_key insufficient_credits quote_unavailable enqueue_failed; do
  must $S "\`$code\`"; must $M "\`$code\`"
done
for f in $SKILLS $M; do mustnt $f 'sanitized'; done
must $S 'Known issue:.*before_date'; must $M 'Known issue:.*before_date'

# -- 4. job status: error_class, the customer-safe message, retries
for f in $C $R $M; do must $f 'error_class'; done
must $C 'customer-safe message that includes a reference'
must $C 'while the service is still retrying it'
must $C 'Never resubmit because of a single `error`'
must $C '`input_rejected`'; must $C '`internal`'

# -- 4b. features guidance, the error-null rule, real search timing
must $S 'usually 4–7 \(3–8 works well\)\. At least one is required; there is no fixed maximum'
must $S 'the quoted price is set by the tier, not the feature count'
must $C '`error` is null\*\* \(failed or retrying, reason not available yet\)'
must $C 'treat|permanent failure'
must $R 'failed or retrying'
must $M 'treat the failure as final only if the job still reads `error` at least 30 minutes after'
must $C 'do not treat the first sighting as final'
must $R 'at least 30 minutes after `first_error_at`'
for f in $C $R $M; do mustnt $f 'a permanent failure only when|this is a permanent failure'; done
for f in $S $C $R $M; do must $f '1\.5–2\.5 hours'; mustnt $f 'one to three hours|15–45 minutes'; done

# -- 5. idempotency and both id shapes
must $S 'IDEMPOTENCY_KEY=\$\(cat /proc/sys/kernel/random/uuid 2>/dev/null \|\| uuidgen \|\| python3'
must $S 'One fresh key per \*\*logical submission\*\*|one fresh key per \*\*logical submission\*\*'
must $S 'retry the \*identical\* call with the \*\*same `idempotency_key`\*\*, up to 3 times'
must $S 'resubmit \*\*with a NEW key\*\* only on their confirmation'
must $S 'A new search \(different claim text, features, date or tier\) \*\*must\*\* get a new key'
for f in $SKILLS $M; do must $f '32-character hex'; must $f '20-character|20 characters'; done
must $S '^- idempotency_key:'; must $S '^- tier:'; must $S '^- quoted_credits:'
must $C 'idempotency_key'

# -- 6. connection, URL, key: tools only, key from the environment only, current domains
must $M '/plugin marketplace add IntelliPat-ai/intellipat-mcp'
must $M '/plugin install intellipat-mcp@intellipat'
must $M 'export INTELLIPAT_MCP_API_KEY='
must $M 'defaults to \*\*`https://mcp\.intellipat\.ai/`\*\*'
must $M 'INTELLIPAT_MCP_URL'
must $S 'https://console\.intellipat\.ai'
for f in $SKILLS $M; do
  mustnt $f 'curl |tools/call|jsonrpc'
  mustnt $f 'app\.intellipat\.ai|lambda-url|on\.aws'
  mustnt $f '~/\.claude/plugins/'
done

# -- 7. public repo: no credentials, no internal document paths or infrastructure names
# (this script is excluded: its patterns are the only allowed occurrences)
for f in $(git ls-files 2>/dev/null | grep -v '^tests/check-contract.sh$' || find . -type f -not -path './.git/*'); do
  mustnt "$f" 'ip_[A-Za-z0-9]{12,}|ghp_[A-Za-z0-9]{20,}|AKIA[A-Z0-9]{12,}'
  mustnt "$f" 'docs/[a-z0-9-]+\.md|Secrets Manager|lambda-url'
done

# -- 8. the hook still greps the status vocabulary the skills write
must hooks/session-start.sh 'status: pending\\\|status: processing'
# -- 8b. the hook, RUN: silent with no pending jobs (no stray errors), one namespaced line with one
hook_out() {   # $1 = memory file body; prints the hook's stdout+stderr for a throwaway project
  local t p k; t=$(mktemp -d); p="$t/proj"; mkdir -p "$p"; k=$(echo "$p" | sed 's|/|-|g' | sed 's|^-||')
  mkdir -p "$t/home/.claude/projects/$k/memory"; printf '%b' "$1" > "$t/home/.claude/projects/$k/memory/intellipat_jobs.md"
  (cd "$p" && HOME="$t/home" bash "$OLDPWD/hooks/session-start.sh" 2>&1); rm -rf "$t"; }
OUT=$(hook_out '# Intellipat Jobs\n\n## a\n- status: done\n')
if [ -z "$OUT" ]; then ok; else bad "hook with no pending jobs printed: $OUT"; fi
OUT=$(hook_out '# Intellipat Jobs\n\n## a\n- status: pending\n## b\n- status: processing\n')
if [ "$OUT" = "[2 Intellipat job(s) in progress — run /intellipat-mcp:review-pending-jobs to check status]" ]; then ok; else bad "hook with 2 pending printed: $OUT"; fi

echo "checks: $((PASS+FAIL))  passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
