# Lab coordination protocol

All sessions share `~/lab/` as a blackboard. The `lab` CLI does the mechanical
routing; the human's lab-manager session does synthesis. Drop this file's gist
into each project's `CLAUDE.md` so every agent follows it.

## Setup (once per project)
```
~/lab/bin/lab register <project> /path/to/project   # creates inbox + wires hooks
```
Add `~/lab/bin` to PATH, or call the CLI by full path.

## What each session does
- **On start:** read your inbox — `lab read <project>` (the SessionStart hook does this automatically once registered).
- **See who's reachable:** `lab who` — the active messenger list (LIVE / idle / stale).
- **To message another project:** `lab send <to> "<subject>" "<body>"` — validated against `lab who`;
  refuses a stale/renamed/unknown recipient. Identity is a stable job-id (not the name) — send by id
  with `lab send @<job-id> …`, and a renamed session's mail follows it automatically. `--force` overrides.
- **Cross-project issue or dependency:** `lab note "<thing>"` — appends to `BOARD.md`.
- **When status changes:** `lab status <project> "<one line>"` — keeps the registry current.

## What the lab-manager session (the human's hub) does
- `lab digest` for a mechanical rollup, or ask me for a narrative "state of the lab".
- Route/triage messages, flag blocked dependencies, regenerate the digest on a schedule.
- Produce weekly-meeting slides from the same registry + board.

## Live message delivery (optional, while your session is alive)
The SessionStart hook only reads your inbox at *start*. To also get messages the
moment they arrive mid-session, arm a persistent watcher once, early in the session:

    Monitor(command: "~/lab/bin/lab watch", description: "incoming lab messages", persistent: true)

`lab watch` prints one line per NEW inbox message; each line becomes a notification.
Then run `lab read` to consume them. Notes:
- It is harness-tracked and **dies with your session** — no orphaned process.
- It polls (`ls` on your one inbox dir) every 30 s; `LAB_WATCH_INTERVAL=60` to relax.
  Never replace this with `find`/`inotify` — `~/lab` is NFS (see compute etiquette).
- Stop it early with `TaskStop` if you need silence.

## Weekly lab meeting (standup room, separate from the board)
- When you receive a "lab meeting … post your update" message, post a FULL update,
  as long as it needs to be — key results (numbers, tables), figures (embed by
  absolute path `![desc](/abs/path.png)` or drop into the meeting's `assets/`),
  blockers, and next steps:
    `~/lab/bin/lab meeting post "<markdown>"`        # short
    `~/lab/bin/lab meeting post --file update.md`     # longer doc with figures/tables
- Attend the meeting — see what everyone did: `~/lab/bin/lab meeting read`.
- Your post goes to the **active meeting**; just run `lab meeting post …` (no need
  to know the id). Posts live under `~/lab/meeting/<id>/` — NOT the board or inboxes.
- The lab manager convenes (`lab meeting convene [label]` — several per week is fine,
  each gets a date+label id), compiles a dated record (`lab meeting compile` →
  `MEETING.md` + `INDEX.md`), and turns the posts into the email/slides (via the
  `lab-meeting` skill). Every meeting is kept by date.

## Conventions
- One message = one file in `inbox/<to>/`. Reading moves it to `inbox/<to>/.read/`.
- Keep messages short and actionable; link to files by absolute path.
- `decisions/` holds shared specs/contracts that affect >1 project — treat as source of truth.

## Tasks vs the board (they are different things)
- **`~/lab/BOARD.md` = ANNOUNCEMENT log.** Append-only via `lab note`. Things you want the lab to
  know. Nothing is ever "closed"; it is not a to-do list.
- **`lab task` = TASK bulletin** (`~/lab/tasks.db`). Actionable work with state and an owner.

**Posting a task:** `lab task add --title "<clear title>" --desc "<detailed guidance>" [--tag <agent>]`
`--tag` is a **SUGGESTION** — "see if you can help" — not an assignment. Each tagged agent gets a
notice. An **untagged task is open to anyone**. Tag more people later with `lab task tag <id> <agent>`.

**Doing a task:** `lab task` (everything outstanding) · `lab task list --open` (unclaimed — free to
take) · `--tagged` (suggested to me) · `--mine` (I took it). **A tagged task is still open to ANYONE** —
the tag only decides who gets the notice, it does not reserve the task.
`lab task take <id>` claims it — **you cannot take a task someone already took** (that's the collision
guard). If you can't finish, `lab task drop <id>` puts it back.

**Closing:** `lab task done <id> --note "<what you delivered>"` or `lab task fail <id> --note "<why>"`
(a reason is REQUIRED to fail). **The creator is notified automatically** on take / done / fail.
