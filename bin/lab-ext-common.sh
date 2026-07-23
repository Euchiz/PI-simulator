# lab-ext-common.sh — the external-agent PACKAGE layout.
# SOURCED (never executed) by BOTH lab-ext (the manager) and lab-bridge (the daemon), so the
# two can never disagree about where an agent's things live.
#
# Everything about one external agent lives in its own package:
#
#   $LAB_HOME/ext/<agent>/
#       adapter.sh   how to run this CLI                     (required)
#       agent.env    THIS agent's settings                   (optional)
#       brief.md     THIS agent's reviewer brief             (optional)
#       threads      subject -> session id (conversation memory)
#       daemon.log   the daemon's log
#       work/        scratch prompts/outputs — redirect to real scratch with
#                    LAB_EXT_WORK inside agent.env if transcripts get large
#
# Settings precedence:  command line  >  ext/<agent>/agent.env  >  $LAB_HOME/lab.env  >  defaults
# (agent.env is scaffolded using  : "${VAR:=value}"  so a var already set on the command line
#  still wins, while the per-agent value still beats the global one.)
#
# The lock deliberately stays at $LAB_HOME/.watch/<agent>.lock — `lab who` reads that
# directory to decide whether a peer is LIVE, and that contract is shared with `lab watch`.

ext_root() { echo "$LAB_HOME/ext"; }

# Every installed agent package, one name per line.
ext_list_agents() {
  local d
  for d in "$LAB_HOME/ext"/*/; do
    [ -d "$d" ] || continue
    basename "$d"
  done
}

# Move a pre-package install into its package. Idempotent; safe to call on every start.
ext_migrate_legacy() {
  local key="$1" pkg="$LAB_HOME/ext/$1"
  mkdir -p "$pkg"
  # adapter: $LAB_HOME/adapters/<key>.sh -> ext/<key>/adapter.sh
  [ -f "$pkg/adapter.sh" ] || [ ! -f "$LAB_HOME/adapters/$key.sh" ] || {
    cp "$LAB_HOME/adapters/$key.sh" "$pkg/adapter.sh"
    echo "lab ext: migrated adapter -> $pkg/adapter.sh" >&2; }
  # conversation memory: .watch/<key>.threads -> ext/<key>/threads  (must not be lost)
  [ -f "$pkg/threads" ] || [ ! -f "$LAB_HOME/.watch/$key.threads" ] || {
    cp "$LAB_HOME/.watch/$key.threads" "$pkg/threads"
    echo "lab ext: migrated threads  -> $pkg/threads" >&2; }
}

# ext_paths <agent> — define every path for one agent, and load its settings.
# Sets: KEY PKG AGENT_ENV INBOX LOCK THREADS LOG LOGDIR WORK BRIEF ADAPTER
ext_paths() {
  KEY="$1"
  PKG="$LAB_HOME/ext/$KEY"
  AGENT_ENV="$PKG/agent.env"

  # Per-agent settings. A syntax error here must not take the agent down silently.
  if [ -f "$AGENT_ENV" ]; then
    if bash -n "$AGENT_ENV" 2>/dev/null; then set -a; . "$AGENT_ENV"; set +a
    else echo "lab ext: WARNING — $AGENT_ENV has a syntax error and was IGNORED (values with spaces need quotes)" >&2; fi
  fi

  INBOX="$LAB_HOME/inbox/$KEY"
  LOCK="$LAB_HOME/.watch/$KEY.lock"     # shared liveness contract with `lab who`
  THREADS="$PKG/threads"
  LOGDIR="$PKG"
  LOG="$PKG/daemon.log"
  WORK="${LAB_EXT_WORK:-$PKG/work}"     # per-agent by construction
  BRIEF="${LAB_EXT_BRIEF:-$PKG/brief.md}"

  ADAPTER=""
  for c in "${LAB_EXT_ADAPTER:-}" "$PKG/adapter.sh" \
           "$LAB_HOME/adapters/$KEY.sh" "$SELF/../adapters/$KEY.sh"; do
    [ -n "$c" ] && [ -f "$c" ] && { ADAPTER="$c"; break; }
  done
}
