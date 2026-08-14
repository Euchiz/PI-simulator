#!/usr/bin/env bash
# tests/test_lab_know.sh — the STATUS-AWARE retrieval guarantee (knowledge-map spec §6):
# a read must NEVER return a retracted or superseded claim as if it were current. This is the
# anti-poisoning invariant the whole ledger exists to protect, so it gets an explicit test.
# Runs lab-know against a throwaway LAB_HOME; prints each check; exits non-zero on any failure.
#   Run: bash tests/test_lab_know.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KNOW="$HERE/bin/lab-know"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export LAB_HOME="$T" LAB_FROM="test"
K(){ python3 "$KNOW" "$@"; }
fail(){ echo "FAIL: $*"; exit 1; }
ok(){ echo "  ok: $*"; }

# 1) setting is REQUIRED (the field that makes retracted-under-confound vs holds-under-a-tweak tractable)
K add --statement "no setting" --kind result 2>/dev/null && fail "add without --setting must error" || ok "add requires --setting"

# 2) add a holds claim, then supersede it with a refined one
K add --statement "zeta measurement original value" --kind result --status holds --setting "setting A" >/dev/null
OLD=$(K list --status holds | awk '/zeta measurement original/{print $2; exit}')
[ -n "$OLD" ] || fail "could not create OLD claim"
K add --statement "zeta measurement refined value" --kind result --status holds --setting "setting B" --supersedes "$OLD" >/dev/null
NEW=$(K list --status holds | awk '/zeta measurement refined/{print $2; exit}')
[ -n "$NEW" ] || fail "could not create NEW claim"
K show "$OLD" | head -1 | grep -q "SUPERSEDED" || fail "OLD should be SUPERSEDED after --supersedes"
ok "supersede flips OLD -> superseded, NEW is current"

# 3) THE GUARANTEE — find must not present the superseded claim as current
out="$(K find 'zeta')"
current="$(printf '%s\n' "$out" | sed '/not current/,$d')"     # section before 'not current'
notcur="$(printf '%s\n' "$out" | sed -n '/not current/,$p')"   # 'not current' section onward
printf '%s' "$current" | grep -q "$NEW" || fail "find CURRENT set must contain NEW ($NEW)"
printf '%s' "$current" | grep -q "$OLD" && fail "find CURRENT set must NOT contain superseded OLD ($OLD)"
printf '%s' "$notcur"  | grep -q "$OLD" || fail "superseded OLD must be shown under 'not current'"
printf '%s' "$notcur"  | grep -q "$NEW" || fail "'not current' entry must point to live successor NEW"
ok "find: superseded claim never in CURRENT; shown as not-current -> live successor"

# 4) retract — excluded from list default, present under --all, never as current
K add --statement "eta throwaway result" --kind result --status holds --setting "setting C" >/dev/null
R=$(K list --status holds | awk '/eta throwaway/{print $2; exit}')
K retract "$R" --reason "confounded" >/dev/null
K list       | grep -q "$R" && fail "list default must EXCLUDE retracted ($R)"
K list --all | grep -q "$R" || fail "list --all must INCLUDE retracted ($R)"
printf '%s' "$(K find 'eta throwaway')" | sed '/not current/,$d' | grep -q "$R" && fail "retracted must not appear as current in find"
ok "retract: excluded from list default + from find CURRENT, present in --all"

# 5) facts — settled-fact + holds only (an open settled-fact is not yet a fact)
K add --statement "theta settled truth" --kind settled-fact --status holds --setting "always" >/dev/null
K add --statement "iota tentative idea" --kind settled-fact --status open  --setting "maybe"  >/dev/null
K facts | grep -q "theta settled truth" || fail "facts must include settled-fact + holds"
K facts | grep -q "iota tentative idea" && fail "facts must EXCLUDE non-holds settled-facts"
ok "facts: settled-fact + holds only"

echo "ALL TESTS PASSED"
