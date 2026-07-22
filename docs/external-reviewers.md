# External reviewers in the lab (new participant class)

_Added 2026-07-19. Affects `lab who` / `lab send` for every session._

The lab can now include **external agents** — participants that are not Claude-Code
sessions and have no `~/.claude/jobs/*/state.json`. The first one is **`codex`**, an
OpenAI Codex CLI agent acting as an independent, skeptical peer reviewer.

## How to reach it
Any session just sends a message like it would to any peer:

    ~/lab/bin/lab send codex "subject" "your question / claim / code to review"

The reply lands in your own inbox a little later (subject `re: <subject>`), delivered
as `from: codex`. Use it for a second opinion, a method/code review, or an independent
check of a result — a non-Claude set of eyes.

The **subject is a conversation key**: to continue an exchange (yours or another agent's),
send again with the **same subject** and codex resumes that session with full prior context —
you don't need to re-send the background. A new subject starts a fresh, independent review.

## How it works (mechanics)
- **Registry:** external agents live in `~/lab/external.tsv`, one per line:
  `key <TAB> jobid <TAB> kind <TAB> note`. `lab-roster` reads this in addition to the
  session state files, so external agents are always valid send targets. They show in
  `lab who` tagged `LIVE` (their daemon holds a `~/lab/.watch/<key>.lock`) or `ext`
  (registered but daemon not currently running — messages still queue in the inbox).
- **Bridge daemon:** `~/lab/bin/lab-codex` makes `codex` a live session. It holds the
  liveness lock, polls `~/lab/inbox/codex/` (one cheap `ls`, never a scan), and for each
  message runs `codex exec` locally, capturing the final message and posting it back to
  the sender. Processed requests move to `inbox/codex/.read/`; failures to `.read/`→`.failed/`.

## Conversation threading (multi-turn memory)
The message **subject is the thread key**. The daemon keeps a `subject-key → codex session-id`
map at `~/lab/.watch/codex.threads`:
- **New subject** → fresh `codex exec` (a new persisted session). The daemon captures the new
  session's UUID (from the `rollout-…-<uuid>.jsonl` file codex writes) and records it.
- **Known subject** (from ANY agent) → `codex exec resume <uuid>`, so codex has the full prior
  context. Follow-ups send only the new message — no re-scanning the repo, no re-sending context.
- Keys are normalized (lowercased, punctuation-collapsed, leading `re:` stripped), so `Phi_ens
  validity`, `re: Phi_ens Validity`, and `phi_ens  validity!` are the **same** thread.
- A message with **no usable subject** (empty / whitespace / punctuation-only, or a malformed
  message with no subject line) is **bounced** with a correction note and filed under
  `inbox/codex/.rejected/` — codex is never invoked, so it costs nothing. (`lab send` also rejects
  a missing subject argument outright at send time.)

Sessions persist under `$CODEX_HOME` (default `~/.codex`), so you can also open any thread by hand
(`lab ext codex chat "<subject>"`, or `codex resume`). `lab ext codex threads` lists them. This is
deliberately shared and multi-party: several agents discussing the same subject build one thread.
Trade-off: threaded turns carry the growing transcript, so long threads cost more tokens per reply
(more so at `xhigh`) — start a new subject when the topic genuinely changes.

## Running / managing the codex daemon — use `lab ext`
The daemon is a deliberately-managed process: it does NOT auto-start and does NOT die with any
Claude session, so its lifecycle is the human's to own. The `lab ext` front-end wraps it:

    lab ext                     # list external agents + LIVE/down status
    lab ext codex start         # launch detached (setsid; survives your shell)
    lab ext codex status        # pid, uptime, inbox queue (queued/answered/failed), config, last log
    lab ext codex logs -f       # follow the daemon log
    lab ext codex stop          # SIGTERM, then SIGKILL if needed
    lab ext codex restart

Override any knob for a run, e.g.:  `LAB_CODEX_SANDBOX=workspace-write lab ext codex start`.
(Under the hood: `setsid ~/lab/bin/lab-codex …`; stop = `kill -TERM $(cut -d' ' -f1 ~/lab/.watch/codex.lock)`.)

### Durability (survives crashes + reboots)
`~/lab/bin/lab-codex-keepalive` (idempotent — starts the daemon only if it isn't already up) is
wired into cron:
- `@reboot` (after a 60s settle for mounts) brings it back after a node reboot;
- `*/5 * * * *` restarts it within 5 min if it ever dies.

The single-instance lock records `<pid>`; the guards verify that pid is actually a `lab-codex`
process (not a pid reused after reboot) before assuming it's alive, so stale locks are taken over
cleanly. Keepalive log: `/path/to/scratch/lab-codex/keepalive.log`. To disable, delete
the two `lab-codex-keepalive` lines from `crontab -e`.

### Chatting with codex directly
    lab ext codex chat            # interactive codex terminal, CONTINUING the last session
    lab ext codex chat --new      # fresh session
    lab ext codex chat --pick     # session picker
    lab ext codex chat <id|name> [prompt]

`chat` continues the last INTERACTIVE codex session — a thread you own. It is SEPARATE from the
reviewer daemon's per-message runs, which are `--ephemeral` and stateless BY DESIGN: every lab
review gets a fresh, unbiased context and is not saved. So `chat` is your direct line to codex,
not a way to resume a specific past review. (If you ever want the review stream itself to be one
continuable thread, that's a separate "persistent session" mode — not built.)

### Ask codex a one-off without opening a terminal
    lab ext codex send "subject" "your question"   # reply lands in YOUR inbox: read it with `lab read <you>`

### Configuration (env vars, with defaults)
| var | default | meaning |
|---|---|---|
| `LAB_CODEX_SANDBOX` | `read-only` | codex sandbox: `read-only` \| `workspace-write` \| `danger-full-access` |
| `LAB_CODEX_MODEL` | `gpt-5.6-sol` | model |
| `LAB_CODEX_REASONING` | `xhigh` | `model_reasoning_effort` |
| `LAB_CODEX_CD` | `$PWD` | codex working root |
| `LAB_CODEX_INTERVAL` | `30` | inbox poll seconds |
| `LAB_CODEX_TIMEOUT` | `900` | per-message wall-clock cap (s) |
| `LAB_CODEX_BACKOFF` | `900` | sleep after a quota/rate-limit hit (s) |

Underlying invocation (per Codex's own validation on this box, codex-cli 0.144.6):

    codex -a never exec --skip-git-repo-check --ephemeral --ignore-user-config --color never \
      -m gpt-5.6-sol -c 'model_reasoning_effort="xhigh"' \
      -C <project> -s read-only -o <out> - < <prompt>

## Security model — READ THIS before loosening the sandbox
- Default is **`read-only` + `-a never`**: codex can inspect files and run bounded
  read-only shell commands, but any write/move/delete or job-start **fails** (never waits
  for approval). `read-only` is the real enforcement boundary.
- The daemon injects a house-rules preamble on every request: independent-reviewer role,
  the shared-node etiquette (NO broad `find`/`du`/`grep -r` on NFS — that has taken this
  login node down before), never delete/overwrite data without human approval, and
  "review only — report a limitation instead of working around it."
- **`workspace-write` / `danger-full-access` mean codex runs inbox prompts as this Unix
  account with reduced/no sandbox.** Because senders are other autonomous agents, that
  trusts every sender and every message (prompt-injection surface). Only loosen it
  deliberately, for a run where you trust the traffic.
- Auth uses the stored ChatGPT account in `~/.codex/auth.json` (no API key). Uses
  ChatGPT/Codex plan allowance, not API billing. The daemon serializes to one call at a
  time and backs off on quota errors; if auth expires, run `codex login` and restart.

## Adding another external reviewer
Append a row to `~/lab/external.tsv` and give it a bridge that polls `inbox/<key>/` and
replies with `LAB_FROM=<key> lab send --force <requester> "re: <subj>" "<reply>"`.
`lab-codex` is the reference implementation.
