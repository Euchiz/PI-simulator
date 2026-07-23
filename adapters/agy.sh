# adapters/agy.sh — Antigravity CLI (`agy`, Gemini) as a lab external reviewer.
#
# SAFETY POSTURE — read this before changing anything here.
#   agy has no single "read-only" switch (unlike codex's -s read-only). Its headless
#   mode AUTO-DENIES every tool permission, which is the safe default and the one we
#   rely on: this reviewer has NO filesystem, shell or browser access. It answers from
#   the message it is sent, using its own knowledge.
#   Do NOT add --dangerously-skip-permissions: it auto-approves EVERY tool (writes and
#   shell included), and the senders here are other autonomous agents — that is a
#   prompt-injection surface with write access. If you want it to read the repo, grant
#   narrow read-only rules under "permissions.allow" in agy's own settings.json instead,
#   and re-test that it still cannot write.
#
# Settings (put them in $LAB_HOME/lab.env, quoted):
#   LAB_AGY_BIN     path/name of the CLI            (default: agy)
#   LAB_AGY_MODEL   model override                  (default: agy's own configured model)
#   LAB_AGY_EFFORT  low|medium|high                 (default: high)
#   LAB_AGY_STATE   agy state dir                   (default: ~/.gemini/antigravity-cli)

AGY_BIN="${LAB_AGY_BIN:-agy}"
AGY_MODEL="${LAB_AGY_MODEL:-}"
AGY_EFFORT="${LAB_AGY_EFFORT:-high}"
AGY_STATE="${LAB_AGY_STATE:-$HOME/.gemini/antigravity-cli}"

# agy keys each conversation by the directory it was launched from, so every run for this
# agent happens in one stable dir — that is also how we recover the id for threading.
_agy_rundir() { (cd "$(dirname "$PROMPT_FILE")" && pwd); }

adapter_preflight() {
  command -v "$AGY_BIN" >/dev/null 2>&1 || {
    echo "agy: '$AGY_BIN' not found on PATH (set LAB_AGY_BIN in \$LAB_HOME/lab.env)" >&2; return 1; }
  return 0
}

adapter_run() {
  local dir rc prompt policy
  dir="$(_agy_rundir)"

  # Headless agy cannot use tools, so tell it that up front. Without this it may decide to
  # read a file, get auto-denied, and return an EMPTY answer instead of a review.
  policy="You are running headlessly with NO tool access: you cannot read files, run
commands, or browse. Answer only from the message below plus your own knowledge. If
answering properly would require inspecting files, say so plainly and state exactly what
you would need to be shown."
  prompt="$policy

$(cat "$PROMPT_FILE")"

  local args=(--print-timeout "${TIMEOUT}s")
  [ -n "$AGY_MODEL" ]  && args+=(--model "$AGY_MODEL")
  [ -n "$AGY_EFFORT" ] && args+=(--effort "$AGY_EFFORT")
  [ -n "${SESSION_ID:-}" ] && args+=(--conversation "$SESSION_ID")   # resume this thread
  # MUST be last: `--print` consumes the NEXT argument as the prompt text.
  args+=(--print "$prompt")

  ( cd "$dir" && timeout -k 30 "$TIMEOUT" "$AGY_BIN" "${args[@]}" "$prompt" ) \
      >"$OUT_FILE" 2>"$LOG_FILE"
  rc=$?

  # A permission auto-deny yields a notice on stdout and no actual answer. Don't deliver
  # that as if it were a review — fail the run so it is visible in `lab ext agy status`.
  if grep -q 'no output produced' "$OUT_FILE" 2>/dev/null; then
    cat "$OUT_FILE" >>"$LOG_FILE"
    echo "agy: tried to use a tool that headless mode auto-denies; no answer produced." >>"$LOG_FILE"
    : >"$OUT_FILE"
    return 3
  fi
  return $rc
}

# agy records "<cwd> -> conversation id" here after each run; that id resumes the thread.
adapter_capture_session() {
  local dir; dir="$(_agy_rundir)"
  python3 - "$AGY_STATE/cache/last_conversations.json" "$dir" <<'PY' 2>/dev/null
import json, sys
try:
    print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))
except Exception:
    pass
PY
}

adapter_is_transient() {
  grep -qiE 'rate limit|quota|too many requests|429|resource[_ ]exhausted|unavailable|deadline exceeded' \
    "$LOG_FILE" 2>/dev/null
}

# Interactive line to the same conversation, for a human.
adapter_chat() {
  if [ -n "${SESSION_ID:-}" ]; then exec "$AGY_BIN" --conversation "$SESSION_ID" "$@"
  else exec "$AGY_BIN" "$@"; fi
}
