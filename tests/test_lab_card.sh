#!/usr/bin/env bash
# tests/test_lab_card.sh — EXPERIMENT CARDS (C1): the card file format, `lab card new/check/show`,
# `lab claim link-card`, and the "no card, no holds" gate on confirm + aim-log (results only; other
# kinds exempt). Runs lab-know against a throwaway LAB_HOME; exits non-zero on failure.
#   Run: bash tests/test_lab_card.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KNOW="$HERE/bin/lab-know"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export LAB_HOME="$T" LAB_FROM="test"
K(){ python3 "$KNOW" "$@"; }
fail(){ echo "FAIL: $*"; exit 1; }
ok(){ echo "  ok: $*"; }

# experiment dir with a real script + real output file (card floor requires both to exist on disk)
E="$T/exp"; mkdir -p "$E/scripts"
printf 'print("hi")\n' > "$E/scripts/run.py"
printf 'metric\tvalue\nauroc\t0.83\n' > "$E/results.tsv"

# --- scaffold + validate -----------------------------------------------------
K add --statement "poreior beats thermo on 23S" --kind result --status open \
  --setting "E.coli 23S, MINCOV=20, RNA004" --id CL1 >/dev/null
K card new "$E" --claim CL1 >/dev/null
[ -f "$E/CARD.md" ] || fail "card new must scaffold CARD.md"
grep -q "CL1" "$E/CARD.md"        || fail "scaffold must prefill claims: header"
grep -q "MINCOV=20" "$E/CARD.md"  || fail "scaffold must prefill Setup from the claim's setting"
ok "card new scaffolds + prefills from the claim"

K card check "$E/CARD.md" >/dev/null 2>&1 && fail "an unfilled STUB must FAIL check (empty sections)"
ok "check rejects the unfilled stub"

cat > "$E/CARD.md" <<EOF
# CARD: poreior vs thermo on 23S
claims: CL1    aim:     author: test    date: 2026-08-19

## Question
Does poreior beat a thermodynamic prior on 23S?

## Setup
E.coli 23S rRNA, MINCOV=20, RNA004 embeddings.

## Implementation
Ran scripts/run.py under conda env poreior (numpy 1.23).

## Outcome
AUROC 0.83, logged in results.tsv.

## Limitations
Single rRNA; no per-read control.

## Repro
python scripts/run.py --out results.tsv
EOF
K card check "$E/CARD.md" >/dev/null || fail "a filled card with real script+output paths must PASS"
ok "check passes a filled card (real script + output paths exist)"

# a card whose paths DON'T exist must fail even if sections are full
cat > "$E/BADPATHS.md" <<EOF
# CARD: broken pointers
claims: CL1    aim:
## Setup
real content here for setup
## Implementation
ran nonexistent/ghost.py somewhere
## Outcome
see nonexistent/ghost_out.tsv
## Limitations
none stated but text present
EOF
K card check "$E/BADPATHS.md" >/dev/null 2>&1 && fail "paths that don't stat must FAIL the floor"
ok "check rejects non-existent script/output paths"

# --- the gate: no card, no holds (results only) ------------------------------
K confirm CL1 --status holds >/dev/null 2>&1 && fail "result->holds without a card must be BLOCKED"
K show CL1 | head -1 | grep -q '^\[OPEN\]' \
  || fail "a blocked confirm must NOT mutate the claim (must stay open)"
ok "gate blocks result->holds without a card, and leaves the claim open"

K confirm CL1 --status holds --card "$E/CARD.md" >/dev/null || fail "confirm --card (valid) must succeed"
K show CL1 | grep -q "card *:.*CARD.md" || fail "confirm --card must store the pointer"
ok "confirm --card promotes to holds + records the pointer"

K card show CL1 | grep -q "poreior vs thermo" || fail "card show must render the linked file"
ok "card show resolves the pointer and prints the card"

# waiver path
K add --statement "trivial derived ratio" --kind result --status open --setting "arith on CL1" --id CL2 >/dev/null
K confirm CL2 --status holds --no-card "trivial arithmetic, card overkill" >/dev/null \
  || fail "confirm --no-card must succeed"
K show CL2 | grep -qi "waiv" || fail "waiver reason must be recorded + shown"
ok "confirm --no-card records an audited waiver"

# link-card onto an already-holds claim (backfill), clearing the waiver
K add --statement "same-card second claim" --kind result --status open --setting "same 23S run" --id CL3 >/dev/null
K confirm CL3 --status holds --no-card "backfill later" >/dev/null
K link-card CL3 "$E/CARD.md" >/dev/null || fail "link-card must attach a valid card"
K show CL3 | grep -q "card *:.*CARD.md" || fail "link-card must set the pointer (and clear the waiver)"
ok "link-card backfills a card onto an existing holds claim"

# link-card rejects an invalid card
K link-card CL3 "$E/BADPATHS.md" >/dev/null 2>&1 && fail "link-card must reject a card failing the floor"
ok "link-card runs check first (rejects an invalid card)"

# --- exemptions --------------------------------------------------------------
K add --statement "an insight, not a result" --kind insight --status open --setting "meta" --id CL4 >/dev/null
K confirm CL4 --status holds >/dev/null 2>&1 || fail "non-result (insight) -> holds must be EXEMPT from the gate"
ok "insight/lesson/decision/fact are exempt (no card required)"

# aim-log gate mirrors confirm
A(){ python3 "$KNOW" aim "$@"; }
mkdir -p "$T/decisions"
printf '%s\n' '# Aim 1: root' '## Aim 1.1: child' '### Aim 1.1.2: leaf' > "$T/decisions/projectmindtree-draft-zac.txt"
A seed --commit >/dev/null
A log 1.1.2 --result "logged holds result" --setting "s" --status holds >/dev/null 2>&1 \
  && fail "aim log --status holds without a card must be BLOCKED"
A log 1.1.2 --result "logged holds result" --setting "s" --status holds --no-card "fixture" >/dev/null \
  || fail "aim log --status holds --no-card must succeed"
ok "aim log honors the same 'no card, no holds' gate"

echo "ALL CARD TESTS PASSED"
