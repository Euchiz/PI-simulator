# adapters/codex.sh — reference adapter: OpenAI Codex CLI.
#
# Copy this as the model for your own coding CLI. `lab-bridge` sources it and calls the
# four functions below; everything lab-side (inbox, threading, delivery, retries) is the
# bridge's job, not yours.
#
# Given to you by the bridge:
#   $PROMPT_FILE  the request to send (already includes the brief on a new thread)
#   $OUT_FILE     write the reply here — its contents are delivered verbatim
#   $LOG_FILE     write stdout/stderr here for debugging
#   $SESSION_ID   prior session to resume; EMPTY on a new thread
#   $PROJECT      working root; the tool should inspect this read-only
#   $TIMEOUT      seconds
#   $RUN_MARKER   a file stamped just before the run (use it to find files the run created)
#   $AGENT        this agent's lab name

CODEX_BIN="${LAB_CODEX_BIN:-codex}"
[ -x "$CODEX_BIN" ] || CODEX_BIN="$(command -v codex 2>/dev/null || true)"
CODEX_MODEL="${LAB_CODEX_MODEL:-}"
CODEX_REASONING="${LAB_CODEX_REASONING:-xhigh}"
CODEX_SANDBOX="${LAB_CODEX_SANDBOX:-read-only}"
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"

adapter_preflight() {
  [ -n "$CODEX_BIN" ] && [ -x "$CODEX_BIN" ] || {
    echo "codex CLI not found — install it or set LAB_CODEX_BIN" >&2; return 1; }
  # authenticate via the stored account, never a stray key in the environment
  unset OPENAI_API_KEY 2>/dev/null || true
  [ "$CODEX_SANDBOX" = "danger-full-access" ] && \
    echo "[$AGENT]   WARNING: sandbox=danger-full-access — every inbox sender is trusted." >&2
  return 0
}

adapter_run() {
  local mflag=() cflag=()
  [ -n "$CODEX_MODEL" ]     && mflag=(-m "$CODEX_MODEL")
  [ -n "$CODEX_REASONING" ] && cflag=(-c "model_reasoning_effort=\"$CODEX_REASONING\"")
  if [ -n "$SESSION_ID" ]; then
    timeout -k 30 "$TIMEOUT" "$CODEX_BIN" -s "$CODEX_SANDBOX" -a never -C "$PROJECT" \
        "${mflag[@]}" "${cflag[@]}" exec resume "$SESSION_ID" \
        --skip-git-repo-check --ignore-user-config -o "$OUT_FILE" - < "$PROMPT_FILE" > "$LOG_FILE" 2>&1
  else
    timeout -k 30 "$TIMEOUT" "$CODEX_BIN" -s "$CODEX_SANDBOX" -a never -C "$PROJECT" \
        "${mflag[@]}" "${cflag[@]}" exec \
        --skip-git-repo-check --ignore-user-config -o "$OUT_FILE" - < "$PROMPT_FILE" > "$LOG_FILE" 2>&1
  fi
}

# Codex writes a rollout-*.jsonl per session; the newest one created after RUN_MARKER is ours,
# and the last 36 chars of its name are the session UUID.
adapter_capture_session() {
  local day f b
  day="$CODEX_HOME/sessions/$(date +%Y/%m/%d)"
  f="$(find "$day" -maxdepth 1 -name 'rollout-*.jsonl' -newer "$RUN_MARKER" 2>/dev/null | sort | tail -1)"
  [ -n "$f" ] || return 0
  b="$(basename "$f" .jsonl)"; printf '%s' "${b: -36}"
}

adapter_is_transient() {
  grep -qiE 'rate limit|quota|usage limit|too many requests|429|insufficient_quota' "$LOG_FILE" 2>/dev/null
}

# Optional: interactive terminal, resuming this thread's session when there is one.
# Only adapters that support an interactive mode need this; `lab ext <agent> chat`
# reports it as unsupported otherwise.
adapter_chat() {
  local common=( -C "$PROJECT" )
  [ -n "$CODEX_MODEL" ]     && common+=( -m "$CODEX_MODEL" )
  [ -n "$CODEX_REASONING" ] && common+=( -c "model_reasoning_effort=\"$CODEX_REASONING\"" )
  local leave="exit/Ctrl-D to leave; the daemon keeps running."
  case "${1:-}" in
    --new)  shift; echo "[lab ext] new $AGENT session in $PROJECT — $leave" >&2; exec "$CODEX_BIN" "${common[@]}" "$@";;
    --pick) exec "$CODEX_BIN" resume "${common[@]}";;
    --last) shift; echo "[lab ext] resuming most recent session — $leave" >&2; exec "$CODEX_BIN" resume --last "${common[@]}" "$@";;
  esac
  if [ -n "${SESSION_ID:-}" ]; then
    echo "[lab ext] resuming thread \"${1:-}\" (session $SESSION_ID) — $leave" >&2
    shift 2>/dev/null || true; exec "$CODEX_BIN" resume "$SESSION_ID" "${common[@]}" "$@"
  fi
  if [ -n "${1:-}" ]; then
    echo "[lab ext] no thread matches \"$1\"; treating it as a session id." >&2
    local s="$1"; shift; exec "$CODEX_BIN" resume "$s" "${common[@]}" "$@"
  fi
  echo "[lab ext] no prior session — starting fresh. $leave" >&2
  exec "$CODEX_BIN" "${common[@]}"
}
