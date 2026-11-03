#!/bin/bash
# Contract check for the skill text. The plugin is markdown + one hook — there is no code to
# unit-test — so this asserts that every skill and the README teach the CURRENT submit_search
# contract and no longer carry the statements that pre-dated it. Each line is one check.
# Run: bash tests/check-contract.sh   (exit 0 = all checks pass; prints pass/fail counts)
#
# What a pass means: the checks assert PRESENCE of the operative sentences (and ABSENCE of the
# superseded ones) — not their placement in a step, and not that the surrounding prose agrees
# with them. The load-bearing `must` patterns therefore match the instruction sentence itself,
# not a bare token that incidental mentions elsewhere would satisfy.
set -u
cd "$(dirname "$0")/.."
PASS=0; FAIL=0
must()   { if grep -qE -- "$2" "$1"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL  $1 lacks: $2"; fi; }
mustnt() { if grep -qE -- "$2" "$1"; then FAIL=$((FAIL+1)); echo "FAIL  $1 still has: $2"; else PASS=$((PASS+1)); fi; }

S=skills/submit-patent-search.md; C=skills/check-job-status.md; R=skills/review-pending-jobs.md; M=README.md
# -- the key: generated per submission, reused on retry, new for a new search (operative sentences)
must $S 'IDEMPOTENCY_KEY=\$\(cat /proc/sys/kernel/random/uuid 2>/dev/null \|\| uuidgen \|\| python3'
must $S 'One fresh key per \*\*logical submission\*\*'
must $S 'retry the \*identical\* request with the \*\*same `idempotency_key`\*\*, up to 3 times'
must $S 'resubmit \*\*with a NEW key\*\* only on their confirmation'
must $S 'A new search \(different claim text, features, date, or tier\) \*\*must\*\* get a new key'
# -- capability gate: all three branches of Step 4a, as instructions
must $S 'Call `tools/list` and read the `submit_search` entry.s `inputSchema\.properties`'
must $S '"method":"tools/list"'
must $S '`idempotency_key` present → \*\*keyed server\*\*'
must $S 'absent → \*\*legacy server\*\*: it ignores arguments it does not know'
must $S 'If `tools/list` cannot be read \(no response, non-200, or unparsable JSON\), treat the server as legacy for this session'
must $S 'received a 20-character id, the server ignored the key'
# -- both job id shapes accepted everywhere an id is read
for f in $S $C $R $M; do must $f '32-character hex|32-hex'; must $f '20-character|20 characters'; done
mustnt $S '20-char nanoid'
# -- error codes taught
for code in insufficient_credits invalid_idempotency_key invalid_tier charge_failed enqueue_failed; do must $S "\`$code\`"; must $M "\`$code\`"; done
# -- tier
must $S '`tier`'; must $S 'screen'; must $S 'deep'
# -- credits_charged_micros is the amount charged, success-only; the old wording is gone
must $S 'amount actually charged'
mustnt $S 'configured price'
mustnt $S 'NOT proof'
mustnt $M 'NOT proof'
mustnt $S 'failed charge is still reported as success'
mustnt $M 'is not safe to retry'
# -- memory record carries the key and tier so a later check can apply the grace rule
must $S '^- idempotency_key:'; must $S '^- tier:'
must $C 'idempotency_key'; must $R 'idempotency_key'
# -- legacy-server fallback kept
must $S 'legacy server'
# -- hook unchanged in what it greps (status vocabulary)
must hooks/session-start.sh 'status: pending\\\|status: processing'

echo "checks: $((PASS+FAIL))  passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
