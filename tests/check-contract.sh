#!/bin/bash
# Contract check for the skill text. The plugin is markdown + one hook — there is no code to
# unit-test — so this asserts that every skill and the README teach the CURRENT submit_search
# contract and no longer carry the statements that pre-dated it. Each line is one check.
# Run: bash tests/check-contract.sh   (exit 0 = all checks pass; prints pass/fail counts)
set -u
cd "$(dirname "$0")/.."
PASS=0; FAIL=0
must()   { if grep -qE -- "$2" "$1"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL  $1 lacks: $2"; fi; }
mustnt() { if grep -qE -- "$2" "$1"; then FAIL=$((FAIL+1)); echo "FAIL  $1 still has: $2"; else PASS=$((PASS+1)); fi; }

S=skills/submit-patent-search.md; C=skills/check-job-status.md; R=skills/review-pending-jobs.md; M=README.md
# -- the key: generated per submission, reused on retry, new for a new search
must $S 'idempotency_key'
must $S 'cat /proc/sys/kernel/random/uuid|uuidgen|uuid\.uuid4'
must $S 'same `idempotency_key`'
must $S 'NEW key'
must $S 'tools/list'
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
