#!/usr/bin/env bash
# tests/test_lab_tool.sh — the tool registry: add/find/show/update/mv/audit + the invariants that
# keep it trustworthy (required fields, dup-id block, find rc1 on miss so scripts don't assume a
# tool exists, audit stat()s paths). Runs against a throwaway LAB_HOME; exits non-zero on failure.
#   Run: bash tests/test_lab_tool.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$HERE/bin/lab-tool"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export LAB_HOME="$T" LAB_FROM="test"
K(){ python3 "$TOOL" "$@"; }
fail(){ echo "FAIL: $*"; exit 1; }
ok(){ echo "  ok: $*"; }

# 1) required fields
K add --id x --name x 2>/dev/null && fail "add without --invocation/--desc must error" || ok "add requires invocation+description"

# 2) add a real-shaped tool, then find it by PURPOSE (not just name)
K add --id sm --name ShapeMapper --kind conda-env --path "$T" \
  --invocation "conda run -n sm shapemapper ..." --env "PYTHONNOUSERSITE=1" \
  --desc "SHAPE reactivity from mutational profiling" --tags "structure reactivity map" \
  --gotchas "np.int; pin numpy<1.24" --verified --verified-how "ran on test" >/dev/null
K find "reactivity" | grep -q "sm" || fail "find by purpose (reactivity) must return the tool"
K find "reactivity" | grep -qi "numpy<1.24" || fail "find must surface the gotcha"
ok "find by purpose returns path+invocation+gotcha"

# 3) show has the invocation + path
K show sm | grep -q "conda run -n sm" || fail "show must include the invocation"
ok "show renders the full record"

# 4) dup id is blocked
K add --id sm --name y --invocation z --desc w 2>/dev/null && fail "dup id must be blocked" || ok "dup id blocked"

# 5) find on a miss returns rc1 (so a script won't assume the tool exists)
if K find "nonexistent-zzz" >/dev/null 2>&1; then fail "find on miss must return non-zero"; fi
ok "find on miss returns rc1"

# 6) update + mv change fields; audit stat()s the path
K update sm --version "2.2" >/dev/null
K show sm | grep -q "2.2" || fail "update must persist"
K mv sm /no/such/path >/dev/null
K audit 2>/dev/null; rc=$?
[ "$rc" = 2 ] || fail "audit must exit 2 when a path is missing (got $rc)"
K audit 2>/dev/null | grep -q "MISSING" || fail "audit must report the missing path"
ok "update + mv persist; audit flags a missing path (rc2)"

echo "ALL TESTS PASSED"
