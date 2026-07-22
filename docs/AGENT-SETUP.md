# Agent setup runbook

**For the human:** you don't have to install this by hand. Open a Claude Code session in the
directory where you cloned this repo and paste:

> Read `docs/AGENT-SETUP.md` in this repo and set up PI simulator for me. Follow it exactly:
> detect what you can, ask me only what you genuinely can't, and verify at the end.

Everything below is addressed to that agent.

---

## Your task

Install and configure PI simulator for this user, wire their existing Claude Code sessions into
it, and prove it works. Aim for: they type `lab who` at the end and see their agents.

## How to behave

- **Detect before asking.** Most of this is discoverable. Ask only where a wrong guess is
  expensive or unrecoverable (which sessions to register, whether to edit shared project files).
- **Never destroy state.** Never overwrite an existing `$LAB_HOME`, `lab.env`, or blackboard.
  Every step is idempotent — re-running setup on a working install must be safe.
- **Never scan the filesystem broadly.** No `find` / `du` / `grep -r` rooted at `/`, `$HOME`, or a
  mount root. On a shared or network filesystem that can take the machine down for everyone.
  Ask the user for paths instead.
- **Quote every value you write into `lab.env`.** It is *sourced* by the shell; an unquoted value
  containing spaces or parentheses is a syntax error. (The CLI now detects and ignores a broken
  file, but don't create one.)
- **Verify each step**, and tell the user plainly if something didn't work rather than moving on.

---

## Step 1 — Preflight

```bash
python3 -c "import sqlite3; sqlite3.connect(':memory:').execute('CREATE VIRTUAL TABLE t USING fts5(x)')" && echo "python+FTS5 ok"
command -v bash flock git
```
`python3` (with FTS5) and `bash` are required; `flock` is used to serialise writes. If FTS5 is
missing, say so — dataset search won't work — and ask whether to continue.

Also confirm this is Claude Code: `echo "$CLAUDE_JOB_DIR"` should be non-empty. Identity comes
from the harness, so without it the tool can't tell sessions apart. Stop and explain if it's empty.

## Step 2 — Install

```bash
./install.sh              # symlinks bin/ into ~/.local/bin
```
Check the install dir is on `PATH`; if not, tell the user the exact line to add to their shell rc
(don't silently edit their rc — offer it).

## Step 3 — Create the blackboard

Ask: **where should the blackboard live?** (default `~/lab`). It holds inboxes, meetings, tasks and
the dataset registry — small, but it must persist and be visible to every session.

```bash
lab init ~/lab
```
This writes `~/lab/lab.env` with every option commented at its default. If the directory already has
one, `lab init` keeps it — say so rather than replacing it.

Tell the user to add `export LAB_HOME=~/lab` to their shell rc (offer to append it).

## Step 4 — Configure what actually matters

Everything has a working default, so only change what's wrong for this machine. Check these three:

**a) Alert channel.** `notify-send` needs a Linux desktop. Detect:
```bash
[ -n "$DISPLAY" ] && command -v notify-send >/dev/null && echo "desktop notifications ok" || echo "headless"
```
If headless, alerts from the daily health check would go nowhere silently. Ask what they want
(`mail`, a Slack webhook wrapper, a script) and set `LAB_ALERT_CMD` — it receives `"<title>" "<body>"`.

**b) Scratch space** (only if they'll use an external reviewer). Transcripts accumulate, so this
should not sit on a small or nearly-full home filesystem. Check where they have room:
```bash
df -h "$HOME" /tmp 2>/dev/null
```
Ask for a scratch path and set `LAB_EXT_WORK`.

**c) Staleness thresholds.** Defaults assume a lab where a session touched nothing for 24h is
worth flagging. Ask: *"roughly how long can an agent be quiet before you'd want to know?"* Only
write `LAB_STALE_WORKING_H` / `LAB_INBOX_BACKLOG_H` / `LAB_TASK_STALE_D` if their answer differs.

Write settings by appending quoted lines to `$LAB_HOME/lab.env`, then verify:
```bash
bash -n "$LAB_HOME/lab.env" && echo "config parses"
```

## Step 5 — Register their sessions

Ask which Claude Code sessions/projects should participate, and where each one works. Then:
```bash
lab register <name> [/path/to/project]
```
Names should match what the user calls each session. Show them `lab who` afterwards — sessions
appear once they've actually run something, so an empty-ish roster here is normal.

## Step 6 — Teach the agents the protocol

Each participating session needs two things:

1. **Protocol in its `CLAUDE.md`** so it knows the commands at session start. Use
   `examples/CLAUDE.md.example` — **append**, never overwrite an existing `CLAUDE.md`.
2. **A SessionStart hook** so it reads its inbox automatically. See
   `examples/settings.json.example`; merge the `hooks` key into the project's
   `.claude/settings.json` rather than replacing the file.

⚠️ **These are the user's project files, and several sessions may share a directory. Show the exact
diff and get explicit approval before writing.** If a project already has a `SessionStart` hook,
merge — don't clobber.

## Step 7 — External reviewer (optional)

Ask whether they want a second-opinion reviewer: a coding CLI that any session can consult.
Detect what's available:
```bash
for c in codex gemini aider opencode cursor-agent; do command -v "$c" >/dev/null && echo "found: $c"; done
```

- **If `codex` is installed**, a reference adapter already ships — just register and start it.
- **For anything else**, run `lab ext setup <agent>`; it scaffolds
  `$LAB_HOME/adapters/<agent>.sh` and prints the contract. **You write the adapter for them** —
  it's one required function, `adapter_run`: read `$PROMPT_FILE`, write the answer to `$OUT_FILE`,
  noise to `$LOG_FILE`, resume via `$SESSION_ID`, inspect `$PROJECT` read-only. Model it on
  `adapters/codex.sh`. Delete the `ADAPTER_UNIMPLEMENTED` line when done.
- Put tool settings (model, binary, sandbox flags) in `lab.env`, quoted.
- **Keep it read-only.** The reviewer inspects code; it must not modify anything.

Then prove it end-to-end:
```bash
lab ext <agent> start
lab ext <agent> status                     # expect LIVE
lab ext <agent> send "setup smoke test" "Reply with OK if you can read this."
sleep 30 && lab read "$(lab name)"         # the reply lands in your inbox
```
If no reply arrives, check `lab ext <agent> logs` and fix the adapter before declaring success.

## Step 8 — Scheduled jobs (optional)

Offer the jobs in `examples/crontab.example`: a daily health check, dataset-registry maintenance,
and auto-convened meetings. Ask which they want and what times. **Append** to their crontab
(`crontab -l` first — never replace it blind), using absolute paths and `LAB_HOME=…` in each line.

## Step 9 — Verify, then hand over

Run this and show the output:
```bash
lab help                                   # sectioned help
lab who                                    # roster
lab task add --title "setup check" --desc "Confirm the task bulletin works."
lab task                                   # should list it
lab task done 1 --note "verified"
lab data check SOME-ACCESSION              # dedup gate: "NOT FOUND" is the correct answer here
lab ext                                    # external agents, if configured
bash -n "$LAB_HOME/lab.env" && echo "config ok"
```

Then tell the user, in plain language:

- **where the blackboard is**, and that it's data — back it up, don't commit it
- **the four commands they'll actually use**: `lab who`, `lab task`, `lab send`, `lab data check`
- **what you configured and why**, especially anything you changed from a default
- **what you did NOT set up**, and how to add it later
- if you edited any project file, **exactly which ones**

## Common failure modes

| symptom | cause |
|---|---|
| every `lab` command prints a syntax warning | unquoted value in `lab.env` — quote it |
| `lab send` refuses a recipient | that session isn't current; `lab who` shows valid targets |
| a session doesn't see its mail | it hasn't run since delivery; the hook reads the inbox at start |
| external reviewer bounces every message | adapter still the template — implement `adapter_run` |
| reviewer replies never arrive | check `lab ext <agent> logs`; the message stays queued on transient errors |
| health check reports nothing on a headless box | `LAB_ALERT_CMD` unset — `notify-send` fails silently |
