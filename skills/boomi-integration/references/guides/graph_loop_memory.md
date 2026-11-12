# Graph Loop Memory

Cross-session learnings persist in a **centralized markdown vault** — a plain folder of notes linked `[[wikilink]]`-style. The links between notes form a knowledge **graph**; the session-by-session **loop** (recall → apply → capture → consolidate) compounds what the agent knows across projects and sessions. The CLI surface is `<skill-path>/scripts/boomi-memory.sh`.

## Contents
- Why a Markdown Vault
- Vault Location and Layout
- Note Types and Format
- The Loop: Recall, Apply, Capture, Consolidate
- Command Reference
- Session Workflow for the Agent
- Sharing the Vault Across Machines and Teams
- Browsing the Graph in Obsidian (and Open-Source Alternatives)
- What Never Goes in the Vault

## Why a Markdown Vault

The vault is a plain folder of Markdown files — no server, no account, no database. That choice is deliberate:

| Requirement | How the vault meets it |
|---|---|
| Freeware | Obsidian (the reference reader) is free for personal use; the vault itself needs nothing at all |
| Open source | The format is plain text: `grep`, `cat`, any editor. Sync with git or Syncthing (both open source). Open-source readers of the same format: Logseq, Foam (VS Code), SilverBullet |
| Easy setup | `boomi-memory.sh init` (or the first `save`) creates it. Nothing to install for the agent |
| Centralized | One vault lives outside any single project, shared by every workspace on the machine |
| Shareable | Any file-sync mechanism works — a private git remote, Syncthing, a network drive |

A hosted doc (Google Docs/Drive) was rejected: proprietary, needs API credentials the agent shouldn't hold, and not greppable by plain CLI tools. A self-hosted wiki app (Wiki.js, BookStack, Outline) was rejected: server + database setup burden for a use case a folder of files covers.

## Vault Location and Layout

Resolution order: `--vault` flag → exported `BOOMI_MEMORY_VAULT` → the workspace `.env`'s `BOOMI_MEMORY_VAULT` → default `~/.boomi-memory`. One vault serves all projects; keep it outside individual workspaces.

```
~/.boomi-memory/
├── README.md              # What this vault is (created by init)
├── learnings/             # All saved notes (one file per learning)
│   └── map-functions-cannot-be-chained.md
└── hubs/                  # Hand-authored index/MOC notes linking related learnings
    └── Boomi Silent Failures.md
```

## Note Types and Format

Every note is Markdown with YAML frontmatter. `save` writes it; the format is deliberately tool-agnostic.

```markdown
---
title: "Map functions cannot be chained"
type: error-fix
tags: [map, udf]
project: "AcmeMVP-InventorySync"
created: 2026-10-24T10:30:00Z
updated: 2026-10-24T10:30:00Z
---

A plain Map component cannot wire one function's output into another's input.
Fix: package the multi-step pipeline in a User-Defined Function.

## Links
- [[User-Defined Functions]]
```

| Type | Capture when |
|---|---|
| `error-fix` | An error was diagnosed and fixed — the cause→fix pair is the highest-value memory in the vault |
| `learning` | Platform behavior discovered that references don't state clearly (the default type) |
| `pattern` | A reusable design or approach that worked |
| `preference` | A durable user preference ("always show the process names and folder at the end") |
| `environment` | A quirk of this account/runtime ("shared web server is advanced API tier — use API Service Components") |
| `project` | Durable project facts: naming conventions, architecture decisions |

`[[wikilinks]]` are the graph's edges. `save` keeps them **bidirectional**: linking to an existing note appends a backlink under that note's `## Linked Notes`, and saving a note that others already reference backfills its own `## Linked Notes`. A link may point at a not-yet-existing note; the graph connects later when that note is saved.

## The Loop: Recall, Apply, Capture, Consolidate

1. **Recall** — At session start, list what the vault knows (`recent --limit 5`). Before designing anything non-trivial, `search` for the steps/connectors/systems involved. `search "trading partner"` also matches backlinks, so a hub note surfaces everything attached to it.
2. **Apply** — Treat recalled notes as soft knowledge: the platform, the account, or the user's mind may have changed. Verify against current `references/` docs before relying on a memory in generated XML.
3. **Capture** — After a learning moment, save it (see below). Saving with a title that already exists appends a dated `## Update` and merges tags/links — learning compounds rather than duplicating.
4. **Consolidate** — When `stats` reports unlinked notes, link them into related notes or author a hub note in `hubs/` that gathers a topic. Hubs make recall one search away.

Capture triggers worth memorizing:
- A validation error or execution failure resolved after investigation
- A silent-failure pattern confirmed in this account
- A user correction of agent behavior ("don't use Groovy for that")
- An account/runtime quirk (auth tiers, default branch, folder conventions)

Not worth memorizing: anything discoverable from the workspace in seconds (sync state, component IDs), one-off task context, or facts already stated in `references/`.

## Command Reference

```bash
# Bootstrap (also happens automatically on first save) — idempotent
bash <skill-path>/scripts/boomi-memory.sh init

# Save a learning (--body repeatable: blocks joined by a blank line;
# multiline via $'line1\nline2'; --link repeatable)
bash <skill-path>/scripts/boomi-memory.sh save \
  --type error-fix \
  --title "Map functions cannot be chained" \
  --tags "map, udf" \
  --body $'A plain Map cannot wire function outputs together.\nFix: use a User-Defined Function.' \
  --link "User-Defined Functions"

# Search: full text (every word must match, order-free), with optional
# frontmatter filters. Matches titles, tags, bodies, and [[wikilinks]].
bash <skill-path>/scripts/boomi-memory.sh search "map function"
bash <skill-path>/scripts/boomi-memory.sh search --tag udf
bash <skill-path>/scripts/boomi-memory.sh search --type error-fix "message step"

# Print one note (by path, exact title, or filename slug)
bash <skill-path>/scripts/boomi-memory.sh show "Map functions cannot be chained"

# Newest-first list (session-start recall)
bash <skill-path>/scripts/boomi-memory.sh recent --limit 5

# Vault statistics + unlinked notes to consolidate
bash <skill-path>/scripts/boomi-memory.sh stats
```

The tool is local-only: no platform API calls, no credentials, works outside a configured workspace. Tags are normalized (lowercase, dashes); titles must be unique per note — a same-title save updates rather than duplicates.

## Session Workflow for the Agent

```bash
# 1. Session start (after resolving <skill-path>)
bash <skill-path>/scripts/boomi-memory.sh recent --limit 5
bash <skill-path>/scripts/boomi-memory.sh search "<main systems/steps of the user's task>"

# 2. Work. When you hit and fix a real problem, or the user corrects you:
bash <skill-path>/scripts/boomi-memory.sh save --type error-fix \
  --title "<symptom or rule, phrased as a claim>" \
  --tags "<area>" \
  --body "<cause and fix, 1-5 sentences>" \
  --link "<existing related note, if any>"

# 3. End of session, if several notes accumulated:
bash <skill-path>/scripts/boomi-memory.sh stats   # link orphans, consider a hub
```

A save takes seconds — err on the side of capturing. Nothing is ever deleted; updates append.

## Sharing the Vault Across Machines and Teams

The vault is a folder, so any file sync works. Two free, open-source options:

**Git (recommended):** initialize a repo in the vault and add a private remote. Pull before recall-heavy sessions, push after capture-heavy ones. The agent should only run `git push` in the vault with explicit user approval — never autonomously.

```bash
cd ~/.boomi-memory && git init && git add -A && git commit -m "memory: initial"
# Add a private remote (GitHub/GitLab private repo, or a bare repo on a file server):
git remote add origin <private-url> && git push -u origin main
```

**Syncthing:** continuous P2P folder sync between machines with no server and no exposure of history. Pair the devices, share the vault folder.

For team sharing, one vault per team plus a shared remote works; same-timestamp edit conflicts are possible but rare because the tool appends rather than rewrites. **Keep the remote private** — the vault describes your integration estate.

## Browsing the Graph in Obsidian (and Open-Source Alternatives)

Humans can browse the vault any time:

- **Obsidian (free):** Open → "Open folder as vault" → select `~/.boomi-memory`. The built-in graph view renders the `[[wikilink]]` network; backlinks panel works out of the box. No plugins or configuration needed.
- **Logseq** (open source): open the folder as a graph.
- **Foam** (open source, VS Code): workspace mode over the same markdown.
- **SilverBullet** (open source, self-hosted): point it at the folder.

The agent needs none of these — `search`/`show`/`recent` cover recall from the CLI.

## What Never Goes in the Vault

- Credentials, API tokens, passwords — anything from `.env`
- Account IDs, environment IDs, atom IDs (they identify your estate; they also churn)
- Personal data from documents being integrated
- Anything the user marks as sensitive

If a learning is only meaningful with a credential or account identifier in it, describe it generically ("the target runtime", "this account's default branch") and reference where the fact lives instead.
