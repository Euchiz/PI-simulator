# Compute-node mode

Run the lab inside a scheduler allocation instead of on a login node, and rotate it automatically
when that allocation ends.

This is for people running Claude Code agents on an HPC cluster. If your agents live on a laptop or
a server you own, you don't need any of this.

## Why

Long-lived agent sessions are memory-heavy. Seven of them, at roughly 300–500 MB each, do not fit on
a shared login node — ours had 5.9 GB total and four cores, shared with everyone else on the cluster.
The symptom is a machine that swap-thrashes until it becomes unusable for you *and* for every other
user on it. That is not a leak you can fix; it's the wrong place to be running.

A compute allocation solves it: our nodes have 80 cores and a terabyte, and asking for 8 cores and
16 GB is both ample and unremarkable. The cost is that allocations **end**, which is what the rest of
this document is about.

## The model

Three facts shape everything:

- **A session's durable part is its transcript**, a `.jsonl` on shared storage. The process is
  disposable.
- **Processes cannot migrate.** There is no "move" — only *close here, resume there*.
- **Identity follows the name.** A resumed session started with `--name poreior` inherits poreior's
  inbox, roster entry and history, because the lab resolves identity from the session's name.

So a migration is: drain every session to a known-safe state, then resume each transcript on the new
node under its original name.

## The loop

```
   [RUNNING] ── signal at T−8h ──→ [DRAINING] ── all closed ──→ [GREENLIT] ──→ [MOVING] ──→ [RUNNING on the new node]
                     │                                                             ▲
                     └─────────── successor submitted in parallel ─────────────────┘
```

1. The host job carries `--signal=B:USR1@<lead>`, so the scheduler warns it before the walltime ends.
2. On that signal it submits its **successor** and opens a migration, messaging every reachable
   session to wrap up: commit, register datasets and tools, log results as claims, note any in-flight
   batch job ids **in its own transcript**, and close.
3. Stragglers are force-closed at `T−2h` so the loop can never block on an unresponsive session. The
   deadline is not negotiable, so consent cannot gate it.
4. The successor polls, and once the old job is gone it resumes every transcript.

**The dying host never drives the handoff.** It only publishes state to shared storage; the successor
pulls. The actor is always the host that will still exist when the work lands.

## Commands

```bash
lab node start          # submit the host job (settings from lab.env)
lab node status         # where the lab lives, and how long is left
lab node enter          # a shell on the host node
lab node rotate         # trigger the termination sequence now
lab node stop           # cancel the host job

lab migrate depart --stop-sessions   # on the OLD node: drain, stop, verify, hand off
lab migrate status                   # who is still wrapping up
lab migrate move --dry-run           # what WOULD move, and why — read this first
lab migrate move                     # on the NEW node: resume the transcripts
lab migrate aftercheck               # verify, and check no name is live twice
```

`lab migrate move` auto-runs the `lab-setup` skill in each resumed session, so they come back with
identity repaired, inbox consumed, watcher armed — and then **stop**, rather than resuming work
unattended at 3am.

## Configuration

`LAB_HOST_*` in `$LAB_HOME/lab.env`:

```bash
LAB_HOST_PARTITION="${LAB_HOST_PARTITION:-defq}"
LAB_HOST_CPUS="${LAB_HOST_CPUS:-8}"
LAB_HOST_MEM="${LAB_HOST_MEM:-16G}"
LAB_HOST_TIME="${LAB_HOST_TIME:-45-00:00:00}"
LAB_HOST_WARN_HOURS="${LAB_HOST_WARN_HOURS:-8}"
LAB_HOST_FORCE_AT_HOURS="${LAB_HOST_FORCE_AT_HOURS:-2}"
```

Read when the **next** node is submitted, so a retune lands at the next rotation. It cannot change
the allocation you are sitting in — a running job's walltime cannot be extended, so pick it at
submission.

## What moves, and what doesn't

| | |
|---|---|
| **Follows the lab** | messaging, tasks, registries, knowledge map, transcripts (all on shared storage) |
| **Runs from the host job** | daily maintenance, meeting cadence, memory/scan watchers — compute nodes have no `crond`, so the host job schedules them itself, stamp-guarded |
| **Stays on a login node** | external reviewers, because they run where their binaries are installed. Their keepalive is the one thing left on `cron` |
| **Does not survive** | running processes and shells. Batch jobs you submitted are independent and outlive the node — record their ids |

## Things that will bite you

Every one of these was found by running it, not by reading it.

**`sbatch`, never `srun`.** Inside an allocation, `srun` nests into the enclosing job instead of
getting a new node: `srun --mem 64G` from a 2 GB allocation fails with *"Memory required by task is
not available"*. Once your agents live inside an allocation, every `srun` habit silently breaks.

**`--signal` with `--wrap` needs `exec`.** `sbatch --wrap="cmd"` runs your command as a child of
`/bin/sh`, and `B:USR1` targets that shell — which has no trap, so the default action **kills the
job** at the warning instead of handling it. Use `--wrap="exec ..."`, and hold the allocation with
`sleep 60 & wait` so the trap fires promptly.

**A warning lead longer than the walltime fires immediately.** A short test job with an 8-hour lead
rotates the instant it starts. Clamp it.

**`/proc` answers only for the local node.** This is the one that bit three separate times. A pid in
a lock file on shared storage, an inherited environment variable, a state field — none of them tell
you whether something is alive on *another* host. Every occurrence presented the same way: a
perfectly healthy thing reported as dead, or a dead one reported as alive. Prefer the scheduler
(`squeue`), a host-stamped lock, or an outcome you can observe (is the inbox being drained?).

**Resuming does not preserve full history.** `--resume` carries a working context, not the archive —
measured at 25% of entries for one session and **1%** for a long-lived one. Pre-migration transcripts
are the only complete record, and must never be pruned automatically. (They also can't be avoided:
a 250 MB transcript was never going to fit in a context window.)

**Old sessions linger in the session view and are trivial to misclick.** They share a name with the
migrated one, and opening an old one *forks a second live session under the same identity* — two
sessions then consume each other's inbox. The view enumerates job directories, not transcripts, so
moving a stopped session's job dir aside removes it from the view while leaving its transcript
intact.

## Before you migrate for real

1. Confirm a standing multi-day allocation is acceptable to whoever runs your cluster. It is visible
   in accounting, and better asked than assumed.
2. Run `lab migrate move --dry-run` and read it. Anything `UNVERIFIED` means the tool could not prove
   that session's process is dead — do not force past it.
3. Watch the first rotation rather than trusting it unattended.
