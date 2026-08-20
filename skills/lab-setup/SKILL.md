---
name: lab-setup
description: Wire this session into the shared lab and verify the wiring is actually working — resolve/repair its lab identity, consume its inbox, ARM the live message watcher (a tool call no shell can make), load the aims tree, and self-check the lab system for drift, dead watchers, broken pointers and stalled queues. Use when a session starts blank or was force-stopped/restarted, or when asked to "set up the lab system", "re-setup", "self-check", "check the lab wiring", or "am I connected". Reports state only — it never proposes what to work on.
---

# lab-setup

Get a session properly attached to the lab, then prove it is attached.

**The problem this solves:** SessionStart already injects the aims tree, so a restarted session *looks*
oriented. But two things it cannot do are exactly the two that break silently — a session whose job
came back without its name has **no identity** (its `lab read` fails and its mail piles up unread), and
the **watcher is never armed by a hook** (a shell cannot call the Monitor tool, so live delivery is off
until an agent arms it). Both failures are invisible: the session feels fine and simply stops hearing
from anyone.

## 1. Gather + repair identity

Run `~/lab/bin/lab setup`. It prints identity, inbox, your tasks, unclaimed tasks, and the aims tree.

If it reports **no lab identity**, fix it before anything else — everything downstream is scoped to the
name:

- Infer the intended name: check `~/lab/bin/lab who` for a roster entry whose job is gone, and compare
  against the working directory and what this session has been doing.
- If it is obvious (one stale entry matching this project), claim it: `~/lab/bin/lab setup <name>`.
- If it is ambiguous, **ask the user which name this session owns** — guessing wrong steals another
  session's inbox, which is worse than asking.

## 2. Arm live delivery — the step only the agent can take

```
Monitor(command: "LAB_WATCH_INTERVAL=60 ~/lab/bin/lab watch",
        description: "incoming lab messages", persistent: true)
```

Always run it, every time this skill is invoked. It is idempotent by design: a live watcher exits
harmlessly ("duplicate exiting"), a killed or superseded one is taken over. **Never skip it on the
assumption one is still running** — a silently-killed watcher is the common failure, and re-arming is
the only way it gets replaced.

## 3. Self-check the lab system

Report anything that fails; stay quiet about what passes.

| check | command | what is wrong if it fails |
|---|---|---|
| identity resolves | `lab name` | mail is queuing into nobody's inbox |
| watcher holds a lock | `ls ~/lab/.watch/` then `kill -0 <pid>` | live delivery is off; mail only arrives at next startup |
| deployed CLI matches source | `cd ~/PI-simulator && git fetch -q && git status -sb \| head -1`, then `for f in bin/*; do cmp -s "$f" ~/lab/bin/$(basename $f); done` | agents are running a stale `lab`; redeploy with `cp` |
| cron is scheduled | `crontab -l \| grep -c 'know maint\|data maint\|tool maint'` | registries stop refreshing (expect 3+) |
| registries reachable | `lab claim find x >/dev/null; lab data list \| head -1; lab tool list \| head -1` | a DB is locked or corrupt |
| card pointers resolve | `lab know maint 2>&1 \| grep -i 'card audit'` | a claim points at a card file that is gone |
| approvals not stalled | `lab aim pending` | tree edits are waiting on Zac and nobody noticed |
| backfill queue | `lab claim review --no-card` | holds-results with no card and no waiver |

Do **not** run broad filesystem scans as part of this — the registries are the index, and walking NFS
from the login node is forbidden (`find` on a big mount once degraded the node for 26 hours).

## 4. Report state — and nothing else

Close with a few lines of fact:

- who this session is, and whether delivery is live
- anything the self-check flagged, most-actionable first
- what is waiting: unread mail, tasks tagged to this session, pending approvals

**Do not propose what to work on, and do not steer the conversation.** This skill re-attaches
plumbing; it does not set an agenda. A session is often restarted *mid-task*, and an unprompted
"here are three things you could do" pulls the thread off whatever the transcript was actually doing
— the restart should be invisible, not a fresh start. Report the state, then **pick up exactly where
the conversation left off**; if the user asked for something before the restart, that request still
stands. If there is genuinely nothing in flight, stop after the report and wait.

## Notes

- `lab read` **consumes** this session's inbox (that is correct — it is yours). Reading *another*
  session's inbox only peeks; never consume someone else's mail.
- Refresh the knowledge map with `lab map` (nightly cron already does it at 08:21). Regenerating the
  file does **not** update a published claude.ai artifact — that needs a republish.
- If this skill is invoked repeatedly in one session, steps 2 and 3 are still safe to repeat; step 1
  should be a no-op once identity resolves.
