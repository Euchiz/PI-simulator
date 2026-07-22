# PI simulator

**Coordination for a fleet of Claude Code sessions.** Several agents work on one research
program; this gives them a shared blackboard so they can message each other, hand off tasks,
hold standups, and keep one registry of the data they produce — instead of a human copy-pasting
between terminals.

It is deliberately boring: plain files, SQLite, and one `lab` CLI. No server, no daemon
(except optional external reviewers), no dependencies beyond Python 3 and bash.

```
lab who                                   # who can I reach right now?
lab send analysis "schema changed" "…"    # message another session
lab task add --title "…" --desc "…"       # post work anyone can pick up
lab meeting convene                       # open a standup; agents post updates
lab data check <accession>                # do we already have this dataset?
```

## Requirements

- **Claude Code** — identity comes from the harness (`CLAUDE_JOB_DIR`, `~/.claude/jobs/*/state.json`).
  This is a Claude-Code-specific tool; it will not do anything useful without it.
- **Python 3.8+** (stdlib only — `sqlite3` with FTS5) and **bash**.
- A shared filesystem if sessions run on more than one host. NFS is fine and is the tested
  configuration (writes are `flock`-serialised, SQLite runs in rollback-journal mode, never WAL).

## Install

```bash
git clone git@github.com:Euchiz/PI-simulator.git
cd PI-simulator && ./install.sh          # symlinks bin/ onto your PATH
lab init ~/lab                           # create the blackboard (data lives here)
echo 'export LAB_HOME=~/lab' >> ~/.bashrc
lab register analysis /path/to/project   # one per session
```

**Code and data are separate.** The repo is the code; `$LAB_HOME` (default `~/lab`) holds your
blackboard — inboxes, meetings, tasks, registry. Nothing in this repo writes research content.

**Per-install settings** go in `$LAB_HOME/lab.env` (gitignored, sourced automatically). The repo
ships generic defaults; your deployment sets reality — see [`examples/lab.env.example`](examples/lab.env.example):

- **health-check thresholds** — what counts as a stalled session, an unread backlog, a stale task
- **the daily judgement pass** — pick the model, point `LAB_JUDGE_CMD` at any prompt-in/text-out CLI,
  or set `LAB_JUDGE=0` to skip it entirely and just get the raw facts
- **the alert channel** — `LAB_ALERT_CMD` replaces `notify-send`, which only works on a Linux desktop
- **the external reviewer** — model, project root, sandbox, timeouts, and a work dir that should point
  at **scratch** rather than your home filesystem (transcripts accumulate)
- **wording** — drop `$LAB_HOME/templates/meeting-agenda.md` or `tuesday-delta.md` in to replace the
  built-in text without editing code

## What it gives you

| | |
|---|---|
| **Messaging** | Direct session→session mail with a live roster. Identity is a **stable job id**, so a renamed or restarted session never loses mail, and `lab send` refuses a dead recipient instead of dropping the message. |
| **Tasks** | A task bulletin with state. `--tag` is a *suggestion* ("see if you can help"), never a reservation — tagged tasks stay open to anyone. `take` is the claim, and you cannot take an already-taken task. The creator is auto-notified on take/done/fail. |
| **Meetings** | Convene a dated standup; each session posts its own update; compile a permanent record. Several meetings per week are fine. |
| **Dataset registry** | SQLite + full-text search. `lab data check <accession>` before downloading stops re-acquiring data you already have. A dataset isn't "done" until it records *how* it was verified. |
| **Announcements** | `lab note` appends to an append-only board — deliberately **not** a to-do list (that's what tasks are for). |
| **External reviewers** | Optional: run a non-Claude model (e.g. OpenAI Codex CLI) as a read-only peer reviewer any session can consult, threaded by subject. |
| **Health check** | A daily job that reports what's actually wrong — stalled sessions, unread backlogs, stale tasks, dead dataset paths. |

## Design notes (why it's built this way)

- **Identity is the stable job id, not the display name.** Names change; job ids survive rename and
  restart. Renaming a session migrates its inbox automatically.
- **One CLI owns all writes**, guarded by `flock`. No agent opens a database directly.
- **Never scan the filesystem.** The dataset registry *is* the index. A broad `find` over a large
  network mount can degrade a shared login node for everyone.
- **Snapshots are for humans, queries are for machines.** `DATASETS.md` is a rendered convenience
  file and may be stale; live answers come from the CLI.
- **Writes stay O(1).** Rendering and exporting run off the write path (cron/on-demand), so write
  latency doesn't grow with the table.

## Docs

- [`docs/PROTOCOL.md`](docs/PROTOCOL.md) — the conventions agents follow
- [`docs/dataset-registry.md`](docs/dataset-registry.md) — schema + rationale
- [`docs/external-reviewers.md`](docs/external-reviewers.md) — the non-Claude reviewer design
- [`examples/`](examples/) — a `CLAUDE.md` snippet for your agents, a SessionStart hook, a crontab

## Status

Working software, in daily use coordinating a real multi-agent research program. Interfaces may
still move. Issues and PRs welcome.

## License

MIT — see [LICENSE](LICENSE).
