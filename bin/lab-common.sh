#!/usr/bin/env bash
# lab-common.sh — shared helpers + paths for the lab CLI and its family modules.
# SOURCED (never executed) by: lab, lab-msg, lab-meeting. The caller sets
# `set -euo pipefail` before sourcing this. One home for the identity/path plumbing
# so each family module (messaging, meetings, …) can be its own file.

LAB_HOME="${LAB_HOME:-$HOME/lab}"
# Site config: per-install overrides (paths, model, node bin). Never committed —
# the repo ships generic defaults; your deployment sets reality here.
# A syntax error here must not brick every command, so validate before sourcing.
if [ -f "$LAB_HOME/lab.env" ]; then
  if bash -n "$LAB_HOME/lab.env" 2>/dev/null; then set -a; . "$LAB_HOME/lab.env"; set +a
  else echo "lab: WARNING — $LAB_HOME/lab.env has a syntax error and was IGNORED (values with spaces need quotes). Check: bash -n $LAB_HOME/lab.env" >&2; fi
fi

REG="$LAB_HOME/registry.md"
BOARD="$LAB_HOME/BOARD.md"
INBOX="$LAB_HOME/inbox"
ARCH="$LAB_HOME/archive"
# Who plays the lab-manager role. It is just a session key, so the role can be named
# anything — set LAB_MANAGER in lab.env if your manager session is not "lab-manager",
# otherwise the scheduled jobs would write to a mailbox nobody reads.
LAB_MANAGER="${LAB_MANAGER:-lab-manager}"
MEET="$LAB_HOME/meeting"
ACTIVE="$MEET/.active"
# dir of the lab scripts (so a module can find its siblings: lab-roster, lab-msg, …)
SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

ts()    { date +%Y-%m-%dT%H:%M:%S; }
stamp() { date +%Y%m%d-%H%M%S; }
# canonical project/session key: lowercase, non-alnum -> single dash, trimmed.
pkey()  { echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-50; }
slug()  { pkey "$1"; }
die()   { echo "lab: $*" >&2; exit 1; }

# Resolve THIS background session's own name from the harness, canonicalized.
resolve_self() {
  local sid="${CLAUDE_CODE_SESSION_ID:-}" jd="${CLAUDE_JOB_DIR:-}" st=""
  for cand in "$jd/state.json" "$(dirname "${jd:-/x}")/state.json" "$HOME/.claude/jobs/${sid%%-*}/state.json"; do
    [ -f "$cand" ] && { st="$cand"; break; }
  done
  [ -n "$st" ] || return 1
  python3 -c "import json;print(json.load(open('$st')).get('name',''))" 2>/dev/null
}

# This session's STABLE job id (survives rename + restart/resume). Basename of CLAUDE_JOB_DIR.
session_jobid() {
  local jd="${CLAUDE_JOB_DIR:-}" sid="${CLAUDE_CODE_SESSION_ID:-}"
  if [ -n "$jd" ]; then basename "$jd"; elif [ -n "$sid" ]; then echo "${sid%%-*}"; fi
}

# Rename-follows-mail: if THIS session's name changed since we last saw its job id,
# migrate its inbox old->new and rename its registry key. Keyed on the stable job id.
reconcile_self() {
  local jid cur old roster="$LAB_HOME/.roster.tsv"
  jid="$(session_jobid)"; cur="$(pkey "$(resolve_self || true)")"
  [ -n "$jid" ] && [ -n "$cur" ] || return 0
  [ -f "$roster" ] && old="$(awk -F'\t' -v j="$jid" '$1==j{print $2; exit}' "$roster")" || old=""
  if [ -n "${old:-}" ] && [ "$old" != "$cur" ]; then
    if [ -d "$INBOX/$old" ]; then
      mkdir -p "$INBOX/$cur/.read"
      find "$INBOX/$old" -maxdepth 1 -name '*.md' -exec mv -n {} "$INBOX/$cur/" \; 2>/dev/null || true
      find "$INBOX/$old/.read" -maxdepth 1 -name '*.md' -exec mv -n {} "$INBOX/$cur/.read/" \; 2>/dev/null || true
    fi
    sed -i "s/^- \*\*$old\*\*/- **$cur**/" "$REG" 2>/dev/null || true
    echo "lab: session renamed '$old' -> '$cur' (job $jid); inbox + registry key migrated." >&2
  fi
  touch "$roster"
  awk -F'\t' -v j="$jid" -v c="$cur" -v t="$(ts)" 'BEGIN{OFS="\t"} $1!=j{print} END{print j,c,t}' \
    "$roster" > "$roster.tmp" 2>/dev/null && mv "$roster.tmp" "$roster"
}

ensure_init() {
  [ -f "$REG" ]   || echo "# Lab registry — projects, owners, status (managed by \`lab\`)" > "$REG"
  [ -f "$BOARD" ] || printf '# Board — cross-project issues & dependencies\n\n_Add items with \`lab note\`. Owners check this each session._\n' > "$BOARD"
  mkdir -p "$INBOX" "$ARCH"
}

project_for_dir() {
  # Map current working dir to a project via registry "path:" markers.
  local cwd; cwd="$(pwd)"
  [ -f "$REG" ] || return 1
  local m
  m=$(awk -v cwd="$cwd" '
    /^- \*\*/ { name=$0; sub(/^- \*\*/,"",name); sub(/\*\*.*/,"",name) }
    /path: / { p=$0; sub(/.*path: /,"",p); sub(/ .*/,"",p);
               if (p!="?" && index(cwd, p)==1) { print name } }
  ' "$REG" | head -1)
  [ -n "$m" ] || return 1
  echo "$m"
}
