#!/usr/bin/env bash
# tests/test_lab_aim.sh — the AIMS TREE layer: seed/tree/log + the governance invariants that keep
# the tree honest (verdicts asserted-never-inferred, edits gated by Zac's approval, evidence
# status-aware). Runs lab-know against a throwaway LAB_HOME; exits non-zero on failure.
#   Run: bash tests/test_lab_aim.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KNOW="$HERE/bin/lab-know"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/decisions"
printf '%s\n' '# Aim 1: root aim' '- Core: the overall thing' '## Aim 1.1: a child aim' \
  '### Aim 1.1.2: a leaf' '# Aim 2: second root' > "$T/decisions/projectmindtree-draft-zac.txt"
export LAB_HOME="$T" LAB_FROM="test"
A(){ python3 "$KNOW" aim "$@"; }
C(){ python3 "$KNOW" "$@"; }
fail(){ echo "FAIL: $*"; exit 1; }
ok(){ echo "  ok: $*"; }

# 1) seed parses the dotted headings into aim rows
A seed --commit >/dev/null
A tree | grep -q "1.1.2  a leaf  \[proposed\]" || fail "seed/tree must render the dotted hierarchy w/ default verdict proposed"
[ "$(A tree | grep -c '\[proposed\]')" = "4" ] || fail "expected 4 aims seeded"
ok "seed: dotted headings -> aim rows, all proposed"

# 2) log a result onto a node = a claim underneath; evidence shows it
#    (holds now requires the 'no card, no holds' gate; --no-card waives it for this fixture)
A log 1.1.2 --result "leaf result X" --setting "some setting" --status holds --no-card "test fixture" >/dev/null
A show 1.1.2 | grep -q "leaf result X" || fail "aim show must list the logged evidence"
ok "log: result attaches as evidence under the aim"

# 3) verdict is ASSERTED — `set` refuses without --approved-by (Zac's live decision)
A set 1.1.2 --verdict claimed --why x >/dev/null 2>&1 && fail "set without --approved-by must refuse" || ok "set refuses without --approved-by"

# 4) the live fast path applies + records history
A set 1.1.2 --verdict claimed --why "leads" --approved-by zac >/dev/null
A show 1.1.2 | grep -q "\[claimed\]" || fail "set --approved-by must change the verdict"
A show 1.1.2 | grep -q "proposed -> claimed" || fail "verdict change must be recorded in history"
ok "set --approved-by: applies + history recorded"

# 5) gated flow: propose -> pending -> approve applies
A propose set-verdict 1.1 --verdict active --why "underway" --rationale "because" >/dev/null
A pending | grep -q "set-verdict on 1.1" || fail "propose must queue a pending edit"
A show 1.1 | grep -q "\[proposed\]" || fail "proposed edit must NOT apply before approval"
A approve 1 --by zac >/dev/null
A show 1.1 | grep -q "\[active\]" || fail "approve must apply the queued edit"
ok "propose->pending->approve: applies only on approval"

# 6) evidence is status-aware: a retracted claim reads as not-current, never current
cid="$(C list --status holds | awk '/leaf result X/{print $2; exit}')"
C retract "$cid" --reason "wrong" >/dev/null
A show 1.1.2 | grep -q "RETRACTED" || fail "retracted evidence must show as RETRACTED in the aim view"
A show 1.1.2 | grep -q "not current" || fail "aim show must count retracted evidence as not current"
ok "evidence view is status-aware (retracted struck, counted not-current)"

echo "ALL TESTS PASSED"
