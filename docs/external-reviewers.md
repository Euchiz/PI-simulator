# External reviewers in the lab

The lab can include **external agents** — participants that are not Claude Code sessions and have no
`~/.claude/jobs/*/state.json`. An external agent is a coding CLI from *another* vendor, wired in as an
independent, skeptical peer reviewer: any session can send it a question, a claim, or code, and a
second opinion lands back in that session's inbox — a non-Claude set of eyes.

> **Status — codex is the validated one; the rest are experimental.** The mechanism is generic: one
> bridge daemon (`lab-bridge`) driven by a small per-tool **adapter**. **Codex is the single reference
> adapter that is actually validated and in daily use.** The same contract is meant to support other
> tools (Gemini CLI, Aider, opencode, …), but **those adapters are not yet validated — treat them as
> experimental and expect to iterate.** Everything tool-specific below (invocation, sandbox flags,
> `LAB_CODEX_*`) belongs to the codex adapter; the framework around it (`lab ext`, `lab-bridge`,
> threading, delivery, retries) is identical for every tool.

## How to reach it
Any session sends a message like it would to any peer (here, the codex reviewer):

    ~/lab/bin/lab send codex "subject" "your question / claim / code to review"

The reply lands in your own inbox a little later (subject `re: <subject>`), delivered as `from: codex`.
Use it for a second opinion, a method/code review, or an independent check of a result.

The **subject is a conversation key**: to continue an exchange (yours or another agent's), send again
with the **same subject** and the reviewer resumes that thread with full prior context. A new subject
starts a fresh, independent review.

## Architecture: generic bridge + per-tool adapter
- **Bridge daemon — `~/lab/bin/lab-bridge <agent>`** (one per external agent, normally launched by
  `lab ext <agent> start`). Tool-agnostic: it holds the liveness lock, polls `~/lab/inbox/<agent>/`
  (one cheap `ls`, never a scan), threads by subject, enforces the per-request timeout, retries on
  transient errors, and posts the reply back to the sender. None of it knows which CLI it drives.
- **Adapter — `$LAB_HOME/adapters/<agent>.sh`** (or a shipped one under `adapters/`). A few shell
  functions that are the *only* tool-specific code:
  - `adapter_run` — **required.** Run one request: read `$PROMPT_FILE`, write the reply to `$OUT_FILE`,
    noise to `$LOG_FILE`, inspect `$PROJECT` read-only.
  - `adapter_preflight` — optional. Verify the CLI exists / is authenticated.
  - `adapter_capture_session` — optional. Echo a session id so the bridge can thread follow-ups.
  - `adapter_is_transient` — optional. Report whether a failure was a retryable rate-limit / quota.
  - `adapter_chat` — optional. Back an interactive `lab ext <agent> chat`.

  `adapters/codex.sh` is the reference implementation; `adapters/TEMPLATE.sh` is the scaffold that
  `lab ext setup <agent>` copies (it prints the contract and leaves an `ADAPTER_UNIMPLEMENTED` marker
  that fails preflight until you remove it).
- **Registry:** external agents live in `~/lab/external.tsv`, one per line
  (`key <TAB> jobid <TAB> kind <TAB> note`). `lab-roster` reads it alongside the session state files,
  so external agents are always valid send targets — shown in `lab who` tagged `LIVE` (the daemon holds
  `~/lab/.watch/<agent>.lock`) or `ext` (registered, daemon down — messages still queue in the inbox).

## Conversation threading (multi-turn memory)
The message **subject is the thread key**. The bridge keeps a `subject-key → session-id` map at
`~/lab/.watch/<agent>.threads`:
- **New subject** → a fresh run; `adapter_capture_session` records the tool's new session id.
- **Known subject** (from ANY agent) → the adapter resumes that session, so the reviewer has the full
  prior context. Follow-ups send only the new message — no re-scanning the repo, no re-sending context.
- Keys are normalized (lowercased, punctuation collapsed, leading `re:` stripped), so `Phi_ens
  validity`, `re: Phi_ens Validity`, and `phi_ens  validity!` are the **same** thread.
- A message with **no usable subject** is **bounced** with a correction note and filed under
  `inbox/<agent>/.rejected/` — the tool is never invoked, so it costs nothing. (`lab send` also rejects
  a missing subject at send time.)

Deliberately shared and multi-party: several agents on the same subject build one thread. Trade-off —
threaded turns carry the growing transcript, so long threads cost more per reply; start a new subject
when the topic genuinely changes.

## Running / managing an external agent — `lab ext`
The daemon is deliberately managed: it does NOT auto-start and does NOT die with any Claude session,
so its lifecycle is yours to own. `lab ext` wraps it (examples use `codex`):

    lab ext                     # list external agents + LIVE/down status
    lab ext setup <agent>       # scaffold an adapter for a new tool
    lab ext codex start         # launch detached (setsid; survives your shell)
    lab ext codex status        # pid, uptime, inbox queue (queued/answered/failed), config, last log
    lab ext codex logs -f       # follow the daemon log
    lab ext codex stop          # SIGTERM, then SIGKILL if needed
    lab ext codex restart
    lab ext codex threads       # list conversation threads (subject -> session -> last used)
    lab ext codex send "subj" "q"   # one-off; the reply lands in YOUR inbox
    lab ext codex chat          # interactive session, if the adapter defines adapter_chat

### Durability (survives crashes + reboots)
`lab ext keepalive` (idempotent — starts an agent only if it isn't already up) is wired into cron
(the logic lives in `lab-ext`; there is no separate keepalive script):
- `@reboot` (after a 60s settle for mounts) brings it back after a node reboot;
- `*/5 * * * *` restarts it within 5 min if it ever dies.

It keys on `LAB_EXT_AGENT` (default `codex`). The single-instance lock records the pid, and the guards
verify it is actually a `lab-bridge` process before assuming it's alive, so stale locks after a reboot
are taken over cleanly. To disable, delete the two keepalive lines from `crontab -e`.

## Configuration
**Framework knobs** (`LAB_EXT_*`, the same for every tool):

| var | default | meaning |
|---|---|---|
| `LAB_EXT_CD` | `$PWD` | working root the reviewer inspects |
| `LAB_EXT_WORK` | `$LAB_HOME/.work/<agent>` | prompts + outputs — point at SCRATCH, not `$HOME` |
| `LAB_EXT_INTERVAL` | `30` | inbox poll seconds |
| `LAB_EXT_TIMEOUT` | `900` | per-request wall-clock cap (s) |
| `LAB_EXT_BACKOFF` | `900` | sleep after a transient / quota hit (s) |
| `LAB_EXT_ADAPTER` | — | explicit adapter path (otherwise searched by agent name) |
| `LAB_EXT_BRIEF` | `$LAB_HOME/templates/reviewer-brief.md` | override the house-rules preamble |

**Codex-adapter knobs** (`LAB_CODEX_*`, specific to `adapters/codex.sh`):

| var | default | meaning |
|---|---|---|
| `LAB_CODEX_SANDBOX` | `read-only` | `read-only` \| `workspace-write` \| `danger-full-access` |
| `LAB_CODEX_MODEL` | `gpt-5.6-sol` | model |
| `LAB_CODEX_REASONING` | `xhigh` | `model_reasoning_effort` |

The codex adapter's underlying invocation (built from those vars):

    codex -a never exec --skip-git-repo-check --ephemeral --ignore-user-config --color never \
      -m "$LAB_CODEX_MODEL" -c 'model_reasoning_effort="<reasoning>"' \
      -C <project> -s "<sandbox>" -o <out> - < <prompt>

## Security model — READ THIS before loosening the sandbox
(This describes the codex adapter; any adapter you add is responsible for its own sandboxing.)
- Default is **`read-only` + `-a never`**: the reviewer can inspect files and run bounded read-only
  shell commands, but any write / move / delete or job-start **fails** (it never waits for approval).
  `read-only` is the real enforcement boundary.
- The bridge injects a house-rules preamble on every request: independent-reviewer role, shared-node
  etiquette (NO broad `find` / `du` / `grep -r` on NFS — that has taken a login node down before),
  never delete/overwrite data without human approval, and "review only — report a limitation instead of
  working around it." Override the wording at `$LAB_HOME/templates/reviewer-brief.md`.
- **`workspace-write` / `danger-full-access` mean codex runs inbox prompts as this Unix account with a
  reduced / no sandbox.** Because senders are other autonomous agents, that trusts every sender and
  every message (a prompt-injection surface). Only loosen it deliberately, for traffic you trust.
- Codex auth uses the stored ChatGPT account in `~/.codex/auth.json` (no API key) — ChatGPT/Codex plan
  allowance, not API billing. The bridge serializes to one call at a time and backs off on quota errors;
  if auth expires, run `codex login` and restart.

## Adding another external reviewer (experimental)
1. `lab ext setup <agent>` — scaffolds `$LAB_HOME/adapters/<agent>.sh` from the template and prints the
   contract.
2. Implement `adapter_run` (plus any optional functions you need) and delete the `ADAPTER_UNIMPLEMENTED`
   line. Put tool settings (model, binary, sandbox flags) in `lab.env`, quoted.
3. `lab ext <agent> start`, then smoke-test: `lab ext <agent> send "test" "reply OK if you can read this"`.

Keep any adapter **read-only** — the reviewer inspects code; it must not modify anything. Only the codex
adapter has been exercised in practice, so a new tool's adapter should be considered experimental until
you've watched it handle real traffic.
