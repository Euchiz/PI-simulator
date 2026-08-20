# The knowledge map

What the project is trying to prove, what it has concluded, and the trace behind each conclusion.

It is not a document index and not a RAG system. There are no embeddings and no similarity search.
The unit is a **claim**, not a passage, and every claim carries a status — which is the whole point:
a retracted finding must stop being returned as current, and a search index cannot do that.

Three layers, one SQLite file (`~/lab/knowledge.db`):

| layer | what it is | who owns it |
|---|---|---|
| **aim tree** | the prescriptive research program — what you're trying to prove | **you** (edits need your approval) |
| **claims** | assertions with a setting and a status; evidence under an aim | agents, as they work |
| **cards** | the experiment trace behind a claim, as a file beside the work | whoever ran the experiment |

## The aim tree

A hierarchy of aims with dotted ids (`1`, `1.1`, `1.1.3`) — the id *is* the hierarchy. Each node
carries a verdict: `proposed · active · claimed · likely · falsified · deferred · retired`.

**Verdicts are asserted, never inferred.** Logging a result never moves a verdict on its own, and
every change is kept in a history with who set it and why. Structural edits go through a queue:

```bash
lab aim tree                      # the whole program, one line per node
lab aim show 1.1.3                # verdict, why, history, evidence, children
lab aim log 1.1.3 --result "…" --setting "…"     # attach a finding to a node
lab aim propose set-verdict 1.1.3 --verdict likely --rationale "…"
lab aim pending                   # what's waiting on you
lab aim approve <id> --by <you>   # only you can apply it
```

## Claims

One assertion, plus the **setting** that produced it — the conditions, sample, configuration.
`--setting` is required, because "it held" is meaningless without "under what".

Status is one of `open · holds · null · retracted · superseded · confounded`. `open` is where
auto-extracted claims land; nothing is ever promoted automatically.

```bash
lab claim find <topic>            # STATUS-AWARE: current claims only
lab claim add --statement "…" --kind result --setting "…" [--topic caller]
lab claim retract <id> --reason "…" [--superseded-by <new-id>]
lab claim review                  # unconfirmed claims waiting on a human
lab facts                         # settled facts only
```

**Status-aware retrieval is the anti-poisoning property.** Retracted and superseded claims are never
returned in the live set; they appear struck through with a pointer to whatever replaced them. A
withdrawn number that keeps circulating does more damage than one that was never published — the
retraction reaches the author, the number reaches everyone else.

## Experiment cards — "no card, no holds"

A card is a markdown file living **beside the experiment**, not in the database; the ledger stores
only a pointer. Required sections: Setup, Implementation, Outcome, Limitations (Question and Repro
recommended), plus at least one script path and one output-data path that **exist on disk**.

Promoting a `result` claim to `holds` requires `--card <CARD.md>` or an explicit
`--no-card "<reason>"` that gets recorded. Other kinds are exempt; retraction never needs one.

```bash
lab card new <dir> --claim <id>   # scaffold, prefilled from the claim
lab card check <path|claim-id>    # validate the floor
lab claim link-card <id> <path>   # attach (or backfill) a card
lab claim review --no-card        # results still owing one
```

A nightly audit stats every card pointer and flags the ones whose files have gone.

## The visualizer

```bash
lab map                           # -> ~/lab/KNOWLEDGE_MAP.html
```

One self-contained HTML file — no server, no build step, no network access, nothing to install. The
aim tree as a graph you can pan, zoom and click; every claim with its setting, provenance, related
claims and its card rendered inline; filters for what rots quietly — claims attached to no aim,
holds-results missing a card, card pointers that no longer resolve.

Regenerated nightly. `lab know export` emits the same snapshot as JSON if you'd rather query it.

## Try it without committing your project

```bash
./docs/demo/build-demo-map.sh /tmp/demo-lab   # then open /tmp/demo-lab/DEMO_MAP.html
```

Builds the illustrative map shown in the README — a personalised neoantigen mRNA vaccine programme
for resected melanoma, with synthetic numbers — so you can click through a populated aim tree,
a superseded claim and an experiment card before pointing this at real work.

## Design notes

- **Nothing is promoted automatically.** Parsers propose; humans confirm. An agent can log and
  retract freely, but it cannot decide that an aim is proven.
- **A claim without a setting is not a claim.** It's the field that keeps "retracted under a
  confound" and "holds under a tweak" from collapsing into each other.
- **Deprecate, don't delete.** Superseded entries keep resolving so old links still work; they're
  just ranked last and flagged.
- **Never walks the filesystem.** Card validation stats known paths and nothing else. On a shared
  cluster a single careless recursive search once degraded a login node for a day.
