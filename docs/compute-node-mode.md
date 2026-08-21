# Compute-node mode

> ⚠️ **Experimental.** Everything here runs, but the piece that matters most — a full automatic
> rotation from one allocation to the next, unattended — has not yet been observed end to end. It is
> being exercised on a live lab now. Until a rotation has completed on its own, treat this as
> something to supervise, keep the pre-migration transcripts, and expect to intervene.
>
> Verified so far: a hand-run migration (drain → move → aftercheck), and sessions surviving a
> disconnect. Not yet verified: the unattended handoff at the walltime boundary, and the host job
> starting the agent daemon (that path first runs at the next rotation).

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
- **Identity follows the name.** A resumed session started with `--name analysis` inherits that agent's
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
LAB_HOST_PARTITION="${LAB_HOST_PARTITION:-defq}"   # set this to your cluster's partition
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

## Where a session is born decides whether it survives

The agent daemon parents every background session, and inside a scheduler the daemon's **job step**
sets their lifetime. Open a shell with `lab node enter` and start sessions from it, and the daemon is
born inside that shell's step — so the moment you exit the shell, the scheduler tears that step down
and kills every session in it, typically within a minute or two.

Nothing in the session can defend itself. Step membership is fixed when a process starts, so `nohup`
and `setsid` change nothing, and the long-lived `extern` step is owned by root, so a running process
cannot be moved somewhere safer after the fact.

The host job therefore starts the daemon itself, in the batch step, which lasts as long as the
allocation. Sessions it parents survive interactive shells coming and going, and `lab node enter`
warns you if it finds a daemon that was started the other way instead.

If you do need to hold a shell open, run `lab node enter` inside `tmux` or `screen` on the login node
and **detach** rather than exiting. The step stays alive because the client does.

## Two rules that change once you are inside an allocation

**Use `sbatch`, never `srun`, for compute.** Inside an allocation `srun` nests into the enclosing job
rather than requesting a new one, so it is capped by that job's resources — asking for more memory
than your allocation holds simply fails. `sbatch` always creates an independent job and behaves the
same everywhere, including from inside another job. Submitted jobs also outlive the node, so record
their ids if anything downstream needs the result.

**Never prune a pre-migration transcript.** Resuming carries a working context, not the full archive,
so a resumed session holds a fraction of its original conversation. The pre-migration transcripts are
the only complete record. `move` backs each one up before touching it, and nothing is ever pruned
automatically.

## Before you migrate for real

1. Confirm a standing multi-day allocation is acceptable to whoever runs your cluster. It is visible
   in accounting, and better asked than assumed.
2. Run the dry run (`lab migrate move --dry-run`) and read it. Any session marked `UNVERIFIED` means
   the tool could not prove its process is dead — do not force past it.
3. Watch the first rotation rather than trusting it unattended.
