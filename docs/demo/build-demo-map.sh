#!/usr/bin/env bash
# Build an ILLUSTRATIVE demo knowledge map — the one in docs/knowledge-map.png.
#
# Subject: a personalised neoantigen mRNA vaccine programme for resected melanoma. The science is
# public and well known; every NUMBER here is synthetic, and it is deliberately not attributed to
# any real company, trial or dataset.
#
# Two uses:
#   1. See what a populated knowledge map looks like before committing your own project to one.
#   2. Regenerate the README figure after a UI change.
#
#   ./docs/demo/build-demo-map.sh [target-dir]     # default: ./.demo-lab
#   open <target-dir>/DEMO_MAP.html
#
# To regenerate docs/knowledge-map.png exactly, preselect the falsified aim before shooting:
#   node -e 'p="<target>/DEMO_MAP.html";fs=require("fs");s=fs.readFileSync(p,"utf8");
#     fs.writeFileSync(p,s.replace("</body>","<script>addEventListener(\'load\',()=>select(\'aim\',\'1.3.3\'))</script></body>"))'
# then screenshot it at 1500x940, deviceScaleFactor 2 (playwright/chromium or any headless browser).
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
BIN="$REPO/bin"
LAB="${1:-$REPO/.demo-lab}"
export LAB_HOME="$LAB" LAB_FROM="demo"
K(){ python3 "$BIN/lab-know" "$@"; }
A(){ python3 "$BIN/lab-know" aim "$@"; }

mkdir -p "$LAB/decisions" "$LAB/inbox"
cat > "$LAB/decisions/projectmindtree-draft-zac.txt" <<'TREE'
# Aim 1: Deliver an individualised neoantigen mRNA therapy that extends recurrence-free survival in resected melanoma
## Aim 1.1: Identify true tumour-specific neoantigens from one resection specimen
### Aim 1.1.1: Call somatic variants at clinically usable sensitivity from WES + RNA-seq
### Aim 1.1.2: Rank candidates by MHC-I presentation, not binding affinity alone
### Aim 1.1.3: Confirm predicted epitopes are actually presented on tumour HLA
## Aim 1.2: Manufacture a patient-specific construct inside the clinical window
### Aim 1.2.1: Hold vein-to-vein turnaround under six weeks at scale
### Aim 1.2.2: Formulate the LNP for reproducible intramuscular delivery
## Aim 1.3: Show the therapy is immunogenic and clinically beneficial
### Aim 1.3.1: Elicit de novo neoantigen-specific CD8 T-cell responses
### Aim 1.3.2: Improve recurrence-free survival on top of anti-PD-1
### Aim 1.3.3: Predict responders from pre-treatment tumour mutational burden
## Aim 1.4: Extend the platform to other resected solid tumours
TREE
A seed --commit >/dev/null

v(){ A set "$1" --verdict "$2" --why "$3" --approved-by demo >/dev/null; }
v 1     active   "Phase 2 readout supports continuing; confirmatory study not yet powered."
v 1.1   claimed  "Two orthogonal callers agree on 91% of called neoantigens in the demo cohort."
v 1.1.1 claimed  "Sensitivity 94% against the matched-normal truth set at 100x tumour depth."
v 1.1.2 likely   "Presentation-aware ranking beats affinity-only, but only above 8 mut/Mb."
v 1.1.3 active   "Immunopeptidomics running on 6 of 20 specimens."
v 1.2   active   "Turnaround is the binding constraint, not chemistry."
v 1.2.1 active   "Median 41 days; the tail past 60 days is sequencing queue, not synthesis."
v 1.2.2 claimed  "Ionisable lipid ratio locked; batch-to-batch potency CV under 12%."
v 1.3   active   "Immunogenicity established; survival benefit still accruing."
v 1.3.1 likely   "De novo CD8 responses in 11 of 16 evaluable patients."
v 1.3.2 active   "RFS curves separate after month 9; too few events to call."
v 1.3.3 falsified "TMB did not predict response once stage and prior therapy were controlled for."
v 1.4   proposed "Blocked on 1.2.1 — turnaround must come down before another indication."

# --- an experiment card with real files on disk (the card floor requires them to exist) ---
E="$LAB/research/neoantigen_ranking"; mkdir -p "$E/scripts"
cat > "$E/scripts/rank_epitopes.py" <<'PY'
"""Rank candidate neoantigens by predicted MHC-I presentation (illustrative demo)."""
PY
printf 'method\tAUROC\tn\npresentation_aware\t0.81\t412\naffinity_only\t0.67\t412\n' > "$E/ranking_auroc.tsv"
cat > "$E/CARD.md" <<'CARD'
# CARD: presentation-aware ranking vs affinity-only
claims: rank-01    aim: 1.1.2    author: demo    date: 2026-08-20

## Question
Does ranking neoantigens by predicted MHC-I presentation beat ranking by binding affinity alone?

## Setup
412 candidate epitopes from 20 resected melanoma specimens, matched normal WES + tumour RNA-seq.
Held-out validation against mass-spec immunopeptidomics. Synthetic illustrative data.

## Implementation
Ran scripts/rank_epitopes.py (presentation model v3) under conda env neoag, scikit-learn 1.4.

## Outcome
Presentation-aware AUROC 0.81 vs affinity-only 0.67; numbers in ranking_auroc.tsv.

## Limitations
Advantage disappears below ~8 mut/Mb, where too few candidates survive filtering to rank.
Single centre; HLA-A*02:01 over-represented. Does NOT show a clinical benefit.

## Repro
python scripts/rank_epitopes.py --in candidates.vcf --out ranking_auroc.tsv
CARD

add(){ K add --statement "$1" --kind "$2" --status open --setting "$3" --id "$4" --author "$5" >/dev/null; }

add "Presentation-aware ranking beats affinity-only ranking for neoantigen selection (AUROC 0.81 vs 0.67)" \
    result "412 epitopes, 20 resected specimens, held-out immunopeptidomics validation" rank-01 immunoinformatics
K confirm rank-01 --status holds --card "$E/CARD.md" >/dev/null
K aim link rank-01 1.1.2 >/dev/null

add "A concatemer encoding up to 34 neoantigens elicits both CD4 and CD8 responses in the same patient" \
    result "phase 1 dose escalation, 16 evaluable patients, 1 mg IM every 3 weeks" concat-01 immunology
K confirm concat-01 --status holds --no-card "readout summarised in the trial report, no standalone card" >/dev/null
K aim link concat-01 1.3.1 >/dev/null

add "Tumour mutational burden above 10 mut/Mb predicts vaccine response" \
    result "retrospective, 16 patients, univariate analysis" tmb-01 biostats
K confirm tmb-01 --status holds --no-card "superseded before a card was written" >/dev/null
K aim link tmb-01 1.3.3 >/dev/null

add "TMB does not predict vaccine response once stage and prior anti-PD-1 exposure are controlled for" \
    result "same 16 patients, multivariable model with stage and prior therapy as covariates" tmb-02 biostats
K confirm tmb-02 --status holds --no-card "negative result, analysis is in the statistical report" >/dev/null
K aim link tmb-02 1.3.3 >/dev/null
K retract tmb-01 --reason "confounded by stage: high-TMB patients were also earlier-stage" --superseded-by tmb-02 >/dev/null

add "Adding a TLR4 agonist to the LNP increases CD8 response magnitude" \
    result "mouse B16-OVA, n=8 per arm, matched lipid molar ratio" tlr4-01 formulation
K confirm tlr4-01 --status null --reason "no separation between arms; reactogenicity increased" >/dev/null
K aim link tlr4-01 1.2.2 >/dev/null

add "Vein-to-vein turnaround is limited by the sequencing queue, not by mRNA synthesis" \
    result "41 consecutive manufacturing runs, per-step timestamps" turn-01 manufacturing
K confirm turn-01 --status holds --no-card "operational metric, tracked in the manufacturing log" >/dev/null
K aim link turn-01 1.2.1 >/dev/null

add "Two orthogonal somatic callers agree on 91% of called neoantigens" \
    result "20 specimens, WES 100x tumour / 50x normal, RNA-seq expression filter" call-01 genomics
K confirm call-01 --status holds --no-card "concordance check, numbers in the pipeline report" >/dev/null
K aim link call-01 1.1.1 >/dev/null

add "Ionisable lipid molar ratio drives batch-to-batch potency more than particle size" \
    result "18 GMP-like batches, potency by in vitro luciferase expression" lnp-01 formulation
K confirm lnp-01 --status holds --no-card "process characterisation, in the CMC package" >/dev/null
K aim link lnp-01 1.2.2 >/dev/null

add "Predicted epitopes are presented on tumour HLA at the rate the model implies" \
    result "immunopeptidomics on 6 of 20 specimens, analysis ongoing" pept-01 immunology
K aim link pept-01 1.1.3 >/dev/null

add "Cryopreserved specimens give the same neoantigen calls as fresh tissue" \
    result "paired fresh/cryo aliquots, 8 specimens" cryo-01 genomics
K aim link cryo-01 1.1.1 >/dev/null

add "RFS curves separate after month 9 in the combination arm" \
    result "interim look, 157 randomised, 34 events, not powered for significance" rfs-01 biostats
K aim link rfs-01 1.3.2 >/dev/null

K app --out "$LAB/DEMO_MAP.html" >/dev/null
echo "built: $LAB/DEMO_MAP.html"
echo "open it in a browser — it is one self-contained file, no server needed."
