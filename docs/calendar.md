# The calendar

Dates the lab must not walk past — and that come and find their owner when they get close.

The lab used to be time-aware in exactly one place: the rotation's `T-8h` wrap-up broadcast. Every
other date lived as free text in a task title or a markdown file, which renders identically on day 39
and on day 1. A date that never fires is a note, not a reminder.

```bash
lab cal add --title "Grant deadline" --on 2026-10-27 --at 23:59 --tz ET --owner manager
lab cal list [--within 30] [--owner X] [--all]
lab cal show <id> · lab cal done <id> · lab cal drop <id>
```

## What makes it different from a task

**An entry is not a task.** Some dates are not actionable at all — *"decisions announced"* is
something to know, not something to do. Entries stand alone; they never need a task to hang off.

**Notices route to the entry's OWNER**, not to whoever runs the daily job. Most dates belong to
someone other than the session hosting the cadence, so `--owner` is what makes the feature useful
rather than a second inbox for one agent. `add` warns immediately if the owner is not a routable lab
key — otherwise the first sign of trouble is the date passing in silence.

**Notices escalate.** Each lead tier fires once and the wording sharpens as the date closes:

| days out | reads as |
|---|---|
| 15+ | `heads-up` |
| 8–14 | `coming up` |
| 4–7 | `SOON` |
| 2–3 | `URGENT` |
| 1 | `TOMORROW` |
| 0 | `TODAY` |
| past | `OVERDUE` (once — it does not nag daily) |

Default tiers are `30,14,7,3,1,0` for a `deadline`, `14,7,3,1,0` for a `milestone`, `7,1,0` for
`info`. Override per entry with `--lead`.

**An entry added late sends ONE notice, at the right urgency.** Add something with 5 days left and
you get a single `SOON`, not a burst of the 30- and 14-day notices it technically already passed.

## Silence is the feature

`lab cal tick` prints and sends nothing unless a tier is crossed that day. This is deliberate: the
daily check earns its attention by being quiet when nothing is wrong, and a calendar that mentioned a
March deadline every morning would spend that credibility inside a week.

## How it runs

`tick` rides the **daily job**, which the host job already schedules and which survives node
rotation. It is not a new channel and it is not `cron` — on a compute node there is no `crond`.

It is called from `lab-daily` rather than from the host job's in-memory schedule loop, because a
running host job holds that loop in memory and would not pick up the call until its next rotation —
which can be weeks away, i.e. after the dates this is meant to catch.

Idempotent by construction: a tier is recorded as fired on the entry, so running `tick` twice in a
day sends nothing the second time. `--dry-run` shows what would fire; `--today YYYY-MM-DD` walks it
forward to test escalation without waiting.

Stored in `$LAB_HOME/calendar.db`, so it rotates with the lab like the other registries.
