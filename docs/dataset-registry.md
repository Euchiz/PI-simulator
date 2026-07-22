# Lab dataset registry — BUILT (2026-07-17)

> **Update 2026-07-17 — super-families.** `accession` is **NO LONGER unique** (a GEO SuperSeries /
> BioProject legitimately spans many datasets). Added a free-text **`subset`** column (which slice).
> `add` **blocks on duplicate `id` only**; a repeated accession **warns + lists siblings** but is allowed.
> `check <accession>` now returns **all** slices under that accession. Register each slice with the real
> accession + `--subset`; never invent sub-accessions (e.g. `ACC12345:partB`). Existing split rows migrated back.


journal). Dispatched as `lab data …`. DB `~/lab/datasets.db` (empty at build). Daily maintenance
`~/lab/bin/lab-data-maint` on cron `15 8 * * *` (render+export+audit). CLAUDE.md rules added to both
shared project dirs. Accession duplicates **BLOCK** (the human's call). `DATASETS.md` = human snapshot only,
NOT a query source (query live via `lab data find/list/show`). DB stores pointers + metadata, never data.

## Goal
One authoritative index of every dataset the lab has downloaded or processed, so agents can
(a) **check before acquiring** (don't re-download data we already have) and (b) **register on
finish** (nothing is "done" until it's in here, verified). Pipeline-agnostic — nanopore today,
anything tomorrow.

## Decisions (from the human)
1. **General, not nanopore-specific.** No hardcoded chemistry column; chemistry lives in free-text tags.
2. **Status = a free-text line the agent writes** so others can just read and understand it — no rigid
   enum. Plus **`updated_by`** = the responsible agent/person to reach out to on confusion.
3. **Keywords = free-text tags** (`illumina`, `nanopore`, `in-vivo`, `timecourse`, `ground-truth`, …),
   **queryable across rows** (FTS handles this).
4. **Duplicate id/accession → BLOCK** with a clear error: *"id 'X' already exists — consider
   `lab data update X`."*
5. **Scope = everything** (raw datasets, GT tables, benchmark bundles, embeddings, …) as long as the
   spec + usage description is clear → required `usage` field.
6. **`samples` = free-text sample clarification** — what's in it at a glance (treated vs control, with/
   without replicates, spike-ins, …).
7. **Write cost must not grow with the table.** So writes touch the DB only; the browsable snapshot +
   backup regenerate on the daily cron + on demand, never on every write (see Performance).

## Schema (SQLite, rollback-journal mode — NOT WAL, because NFS)

```sql
CREATE TABLE datasets (
  id            TEXT PRIMARY KEY,     -- short slug, e.g. study-a-2024   (dup -> BLOCK)
  study_name    TEXT NOT NULL,        -- human study/paper name
  accession     TEXT,                 -- SRA/ENA/GEO/PRJNA...  (UNIQUE; dup -> BLOCK)
  paper_url     TEXT,
  location      TEXT NOT NULL,        -- absolute storage path
  tags          TEXT,                 -- free-text keywords; queryable across rows
                                      --   e.g. "nanopore in-vivo timecourse"
  samples       TEXT,                 -- free-text: what samples are in it, at a glance
                                      --   e.g. "treated x2 + matched control x2 + unmod spike-in"
  status_line   TEXT NOT NULL,        -- the agent's own plain-language current status. Read it,
                                      --   understand it. e.g. "26/26 signal_bams done; verified."
  verified      INTEGER DEFAULT 0,    -- 0/1 — passed a real verification gate (not just exit 0)
  verified_how  TEXT,                 -- what was checked, e.g. "SA/SAindex non-zero; 80% mapped"
  usage         TEXT NOT NULL,        -- what it is + how to use it (required; scope = everything-if-clear)
  size_bytes    INTEGER,              -- cleanup prioritisation (optional)
  n_files       INTEGER,
  md5_checked   INTEGER DEFAULT 0,
  pair_of       TEXT,                 -- id of matched dataset (treated<->control), optional
  role          TEXT,                 -- treated|control|training|validation|benchmark|... optional
  ref_genome    TEXT,                 -- genome/annotation + coord system, optional
  benchmark_valid INTEGER,            -- 1/0/NULL usable as a generalisation benchmark? optional
  benchmark_note  TEXT,               -- e.g. "group-I intron, in RNA-FM pretraining — control only"
  provenance    TEXT,                 -- pipeline commit / command / recipe path, optional
  notes         TEXT,
  added_by      TEXT,                 -- session/agent that created the row (INTERNAL)
  updated_by    TEXT NOT NULL,        -- who last touched it = who to reach out to (INTERNAL)
  created       TEXT NOT NULL,
  updated       TEXT NOT NULL
);
CREATE UNIQUE INDEX ux_accession ON datasets(accession) WHERE accession IS NOT NULL;

CREATE VIRTUAL TABLE datasets_fts USING fts5(
  id, study_name, accession, tags, samples, status_line, usage, notes,
  content='datasets', content_rowid='rowid'
);  -- + insert/update/delete triggers to keep it in sync
```

Required: `id`, `study_name`, `location`, `status_line`, `usage`, `updated_by`. `samples` + `tags` are
strongly recommended (they carry the at-a-glance value). Everything else optional so any pipeline fits.

## CLI (`lab data ...`)
Reads/queries are **live** against the DB (always current, fast at any size — indexed + FTS):
- `lab data check <accession|query>` — **dedup gate.** Match → print row + location, exit non-zero.
- `lab data find <query>` — FTS across id/name/accession/tags/samples/status/usage/notes.
- `lab data show <id>` · `lab data list [--tag nanopore --status …]`

Writes are DB-only (flock-guarded, one transaction — **constant time regardless of table size**):
- `lab data add --id … --study … --location … --status "…" --usage "…" [--tags … --samples … --accession … …]`
  → BLOCKS on duplicate id/accession.
- `lab data update <id> --status "…" [--verified --verified-how "…"] [--tags … --samples … --location … …]`
- `lab data mv <id> <new-location> [--symlink]` — relocation.

Snapshot + maintenance (cron + on-demand, **never on the write path**):
- `lab data render` → `~/lab/DATASETS.md` (browsable snapshot; ~seconds even at 10k rows).
- `lab data export` → `~/lab/datasets.csv` (git-tracked backup; diffable, recoverable).
- `lab data audit` → `stat` every registered `location`, flag missing/dead paths + unverified rows.
  **Never walks a tree.**
- All three run on the daily 8:07am health-check cron; runnable by hand anytime.

## CLAUDE.md rules (to paste into the shared file)
> ### Dataset registry — the single source of truth (`~/lab/datasets.db`)
> 1. **Before acquiring any dataset:** `lab data check <accession>` / `lab data find <keywords>`.
>    Already there and `verified`? Use it — don't re-download.
> 2. **The moment a download/processing step finishes:** register/update it —
>    `lab data add …` or `lab data update <id> --status "<plain-language status>"`. Write the status
>    line so a teammate can read it and understand. Not "done" until `verified` + `--verified-how`.
>    Fill `--samples` so others see the composition (treated/control, replicates) at a glance.
> 3. **Never scan the filesystem to find data.** The registry is the index. Path moved? `lab data mv`.
> 4. **For the current picture, query live** (`lab data find/list/show`) — `DATASETS.md` is a snapshot
>    refreshed on the daily cron. Register from your session (login node), not from inside sbatch.

## Performance (measured)
Full markdown render + CSV export of the whole table: 100 rows ≈ 21 ms · 2,000 ≈ 50 ms · 10,000 ≈ 276 ms
· 50,000 ≈ 2 s. A dataset registry lives in the hundreds–low-thousands, so even on-write would be fine —
but by keeping render/export **off** the write path (cron + on-demand only), **write latency is constant
regardless of size**, and live queries stay fast because they're indexed/FTS, not full renders.

## Reliability
- **Writes:** one CLI, `flock` mutex (same-host login node), rollback-journal mode. No agent opens the
  DB directly.
- **Backup:** `export` on the daily cron → git-tracked `~/lab/datasets.csv` (also run by hand before
  anything risky). The DB write itself is durable; the CSV is for corruption recovery + diffs.
- **Audit + render + export** ride the existing 8:07am cron — no separate step, reuses stable infra.
