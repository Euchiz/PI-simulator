# adapters/TEMPLATE.sh — scaffold for wiring your own coding CLI into `lab ext`.
#
# `lab ext setup <agent>` copies this to $LAB_HOME/adapters/<agent>.sh for you to fill in.
# The bridge (lab-bridge) owns everything lab-side: polling the inbox, threading by subject,
# delivering replies, retries, backoff, the single-instance lock. You own exactly one thing —
# HOW TO RUN YOUR CLI ONCE.
#
# ── what the bridge gives you (already exported) ────────────────────────────────────
#   $PROMPT_FILE  the request to send. On a NEW thread it already contains the reviewer
#                 brief; on a RESUME it contains only the new message.
#   $OUT_FILE     write the reply here. Its contents are delivered verbatim to the asker,
#                 so it must be the answer itself — not a log, not a summary of your run.
#   $LOG_FILE     write stdout/stderr here (used for debugging + transient detection).
#   $SESSION_ID   a prior session id to resume. EMPTY means start a new conversation.
#   $PROJECT      working root; your CLI should inspect it READ-ONLY.
#   $TIMEOUT      seconds allowed for one request.
#   $RUN_MARKER   a file stamped immediately before the run — useful for finding whatever
#                 files your CLI created during it (e.g. a new session/transcript file).
#   $AGENT        this agent's lab name.
#
# Put your own settings in $LAB_HOME/lab.env and read them here with a default, e.g.
#   MY_MODEL="${MY_CLI_MODEL:-some-default}"

# Delete this line once you have implemented adapter_run() below. Until then the daemon
# refuses to start, so you get a clear error instead of one that bounces every message.
ADAPTER_UNIMPLEMENTED=1

# ── REQUIRED ────────────────────────────────────────────────────────────────────────
# Run ONE request. Write the reply to $OUT_FILE. Return the CLI's exit code.
adapter_run() {
  # TODO: replace with your CLI. Two shapes are common:
  #
  #  (a) the CLI can write the answer to a file:
  #     timeout -k 30 "$TIMEOUT" mycli --project "$PROJECT" --out "$OUT_FILE" \
  #         < "$PROMPT_FILE" > "$LOG_FILE" 2>&1
  #
  #  (b) the CLI only prints to stdout — capture stdout as the answer:
  #     timeout -k 30 "$TIMEOUT" mycli --project "$PROJECT" \
  #         < "$PROMPT_FILE" > "$OUT_FILE" 2> "$LOG_FILE"
  #
  # If your CLI supports resuming a conversation, branch on $SESSION_ID:
  #     if [ -n "$SESSION_ID" ]; then ... --resume "$SESSION_ID" ... ; else ... ; fi
  echo "adapter_run not implemented for '$AGENT' — edit $LAB_HOME/adapters/$AGENT.sh" > "$LOG_FILE"
  return 3
}

# ── OPTIONAL ────────────────────────────────────────────────────────────────────────
# Fail fast at startup if the CLI is missing or unauthenticated. Non-zero aborts the daemon.
adapter_preflight() {
  [ -n "${ADAPTER_UNIMPLEMENTED:-}" ] && {
    echo "adapter for '$AGENT' is still the unedited template." >&2
    echo "  implement adapter_run() in \$LAB_HOME/adapters/$AGENT.sh, then delete the" >&2
    echo "  ADAPTER_UNIMPLEMENTED line at the top of it." >&2
    return 1; }
  # command -v mycli >/dev/null || { echo "mycli not found on PATH" >&2; return 1; }
  return 0
}

# Echo the id of the conversation this run created/continued, so the NEXT message with the
# same subject resumes it. Echo nothing if your CLI has no resumable sessions — the bridge
# then simply starts fresh each time (threading is a bonus, not a requirement).
adapter_capture_session() {
  # e.g. your CLI prints "session: <id>" on the last line of its log:
  #   sed -n 's/^session: //p' "$LOG_FILE" | tail -1
  #
  # …or it drops a transcript file; find the one newer than $RUN_MARKER:
  #   f="$(find "$HOME/.mycli/sessions" -maxdepth 1 -newer "$RUN_MARKER" 2>/dev/null | sort | tail -1)"
  #   [ -n "$f" ] && basename "$f" .json
  :
}

# Return 0 when the failure is TRANSIENT (rate limit / quota / 429). The bridge then leaves
# the message queued and backs off instead of bouncing it back as a failure.
adapter_is_transient() {
  grep -qiE 'rate limit|quota|too many requests|429' "$LOG_FILE" 2>/dev/null
}
