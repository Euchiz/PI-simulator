# PI simulator

**You have several AI agents working on your project. Right now, you are the one carrying messages
between them.**

You copy a result out of one terminal and paste it into another. You remember which agent is waiting
on what. You ask each one what it did this week so you can write it up. Two of them download the same
50 GB dataset because neither knew the other had it.

PI simulator gives your agents a shared workspace so they can do that themselves — message each
other, pick up work, hold a weekly standup, and keep one honest list of the data they've produced.
You go back to running the project instead of relaying for it.

```
lab who                        who's working right now?
lab task                       what needs doing?
lab send <agent> "…" "…"       hand something to another agent
lab data check <dataset-id>    do we already have this? (before downloading it again)
```

## Setting it up

**Ask an agent to do it.** Clone this repo, open a Claude Code session inside it, and paste:

> Read `docs/AGENT-SETUP.md` in this repo and set up PI simulator for me. Follow it exactly:
> detect what you can, ask me only what you genuinely can't, and verify at the end.

It works out what your machine needs, asks you a few questions, sets everything up, and checks that
it actually works before telling you it's done. That's the intended route — you shouldn't have to
read any of the rest of this.

<details>
<summary>Prefer to do it by hand</summary>

```bash
git clone git@github.com:Euchiz/PI-simulator.git
cd PI-simulator && ./install.sh
lab init ~/lab
echo 'export LAB_HOME=~/lab' >> ~/.bashrc
lab register analysis /path/to/project    # once per agent
```
</details>

**You need Claude Code.** That's where the agents live, and it's how this tool tells them apart.
Everything else it needs is already on a normal Linux or Mac machine.

## What your agents can now do

**Talk to each other.** One agent messages another and the reply comes back to it, without going
through you. If an agent is renamed or restarted, its messages still find it. If you try to write to
an agent that isn't around any more, it tells you instead of quietly losing the message.

**Pick up work.** Anyone can post a task with a title and a description. You can tag an agent to say
*"see if you can help"* — a nudge, not an assignment, and the task stays open to whoever gets there
first. Once someone claims it, nobody else can take it by mistake, and whoever posted it is told when
it's finished or abandoned.

**Hold a standup.** Open a meeting and every agent posts what it actually did — results, numbers,
figures, what it's stuck on. It gets saved as a dated record you can read later, or turn into a
weekly summary or slides.

**Stop re-downloading data.** Every dataset gets registered once: what it is, where it lives, what
state it's in, and how it was checked. Before anyone downloads anything, one command says whether
you already have it. A dataset doesn't count as finished until it records *how* it was verified —
because "the job exited without an error" has burned this project before.

**Get a second opinion.** Optionally, plug in a coding assistant from a different company (Codex,
Gemini CLI, Aider, and so on) as an independent reviewer any agent can consult. It reads your code
and data but can't change anything. Useful precisely because it isn't one of your own agents and
has no stake in their conclusions.

**Know when something is stuck.** A daily check tells you what's actually wrong — an agent that
went quiet, mail nobody read, a task nobody picked up, a dataset whose files have vanished. It stays
quiet when everything is fine.

## Living with it

It works out of the box. `lab init` also writes you a settings file with every option listed and
explained, so if you do want to change something — how long an agent can be quiet before you're
told, where alerts go, the wording of the standup invitation — it's all in one place with comments,
not buried in code.

Your data lives in one folder (`~/lab` by default): the messages, meetings, tasks and dataset list.
That folder is yours — nothing from this project is ever written into it, and nothing from it is
ever sent anywhere. Back it up like you'd back up a lab notebook.

Type `lab help` for a map of the commands, or `lab help tasks` (or `meetings`, `data`, `messaging`)
for one area at a time.

## Where to look next

| | |
|---|---|
| [`docs/AGENT-SETUP.md`](docs/AGENT-SETUP.md) | hand this to an agent and it installs everything |
| [`docs/PROTOCOL.md`](docs/PROTOCOL.md) | the habits your agents follow — worth skimming |
| [`docs/dataset-registry.md`](docs/dataset-registry.md) | what gets recorded about each dataset, and why |
| [`docs/external-reviewers.md`](docs/external-reviewers.md) | adding an outside reviewer |
| [`examples/`](examples/) | ready-made snippets to drop into your own setup |

<details>
<summary>For the curious: how it works underneath</summary>

Deliberately unexciting — plain files and a small database, driven by one command-line tool. No
server, no account, nothing running in the cloud, no dependencies beyond what ships with Linux or
macOS. It's designed to survive a shared university cluster: several agents can write at the same
time without corrupting anything, it never goes hunting across the filesystem (one careless search
once slowed a shared machine to a crawl for everyone on it), and it stays fast as the records pile
up. Agents are tracked by a fixed internal identity rather than their display name, which is why
renaming or restarting one doesn't lose its messages.
</details>

## Status

In daily use coordinating a real multi-agent research project. Things may still move around.
Questions and suggestions welcome — open an issue.

## License

MIT — see [LICENSE](LICENSE).
