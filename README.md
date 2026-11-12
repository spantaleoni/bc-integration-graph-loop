# bc-integration

The official Boomi Companion — a Claude Code plugin for Boomi platform development. It wraps the boomi-integration skill with plugin-level commands, agents, and workspace tooling.

> **Important:** Boomi Companion is a publicly available developer offering, not an officially supported Boomi product. It is provided as-is and is not covered by Boomi support agreements or SLAs. Boomi curates and maintains this tool on a best-effort basis — treat it as a self-service resource. Boomi reserves the right to modify or discontinue it at any time without notice.

This project is licensed under the [BSD-2-Clause License](LICENSE). If you fork or modify this code, you should not use the name "Boomi" for your version.

## Documentation

For a full overview of Boomi Companion, including concepts, usage guidance, and additional resources, see the [Boomi Companion overview](https://developer.boomi.com/docs/BoomiCompanion/Boomi_companion_overview) on the Boomi Developer Portal.

## Related Plugins & Skills

Other plugins available in Boomi Companion:

| Plugin | Description |
|--------|-------------|
| [bc-marketplace](https://github.com/OfficialBoomi/bc-marketplace) | Skill for searching and installing Boomi Marketplace recipes |

The underlying skills are also available as standalone packages for use with other AI agents, or to fork and modify for your own needs:

| Skill | Description |
|--------|-------------|
| [boomi-integration](https://github.com/OfficialBoomi/boomi-integration) | Skill for building Boomi integrations |
| [boomi-marketplace](https://github.com/OfficialBoomi/boomi-marketplace) | Skill for searching and installing Boomi Marketplace recipes |

See the [Boomi Companion marketplace](https://github.com/OfficialBoomi/boomi-companion) for the complete registry.

## 🧠 Graph Loop Memory (New)

**Cross-session learnings that compound over time.** The boomi-integration skill now includes a centralized memory layer — a plain Markdown vault (default `~/.boomi-memory`) where the agent saves durable learnings: debugging fixes, account/runtime quirks, your preferences, reusable patterns. One vault is shared across **all your Boomi projects** on the machine.

### How it works

| Phase | What happens |
|-------|--------------|
| **Recall** | At session start the agent runs `recent --limit 5` and `search "<topic>"` for the steps/connectors/systems you're working with. Hits are treated as soft knowledge — verified against current docs before use. |
| **Apply** | Recalled learnings inform design choices (e.g., "this account's runtime is Advanced tier → use API Service Components"). |
| **Capture** | After a debugging win, a user correction, or a discovered quirk, the agent saves a note: `save --type error-fix --title "..." --body "..." --link "Related note"`. Same-title saves append a dated update and merge tags/links instead of duplicating. |
| **Consolidate** | `stats` surfaces unlinked (orphan) notes. You or the agent can link them into related notes or author hub notes in `hubs/` — making future recall one search away. |

### Why this vault design?

| Requirement | Solution |
|-------------|----------|
| **Freeware reader** | Obsidian (free for personal use) opens the folder as a vault and renders the `[[wikilinks]]` as a knowledge graph with backlinks. |
| **Open-source alternatives** | Logseq, Foam (VS Code), SilverBullet — all read the same plain Markdown format. |
| **Centralized across machines/teams** | The vault is just a folder. Sync it with **git** (private remote) or **Syncthing** (P2P, no server). Both are free and open source. |
| **No vendor lock-in** | Plain text + `grep` works everywhere. No database, no server, no account. |
| **Security** | The vault is **credential-free by design** — the tool never stores tokens, account IDs, or `.env` values. |

### Tooling

The CLI surface is `boomi-memory.sh` (in `skills/boomi-integration/scripts/`):

```bash
# Bootstrap (idempotent; also happens on first save)
bash <skill-path>/scripts/boomi-memory.sh init

# Save a learning (--body repeatable; --link repeatable; multiline via $'line1\nline2')
bash <skill-path>/scripts/boomi-memory.sh save \
  --type error-fix \
  --title "Message step JSON quote escaping" \
  --tags "message, json" \
  --body $'Wrap substitutions like \x27"{1}"\x27, not "{1}".' \
  --link "Silent failures checklist"

# Search: full text (every word must match, order-free) + frontmatter filters
bash <skill-path>/scripts/boomi-memory.sh search "silent failures"
bash <skill-path>/scripts/boomi-memory.sh search --tag troubleshooting --type error-fix

# Print one note (by title, path, or slug)
bash <skill-path>/scripts/boomi-memory.sh show "Message step JSON quote escaping"

# Session-start recall
bash <skill-path>/scripts/boomi-memory.sh recent --limit 5

# Vault stats + unlinked notes to consolidate
bash <skill-path>/scripts/boomi-memory.sh stats
```

The vault location is configurable via `BOOMI_MEMORY_VAULT` in your workspace `.env` (defaults to `~/.boomi-memory`).

### Human review

Use the new `/bc-integration:memory` command for a readable summary:
- Vault location, total notes, notes per type
- Most recent learnings with one-line gists
- Unlinked notes with consolidation suggestions
- Instructions for browsing the graph in Obsidian or open-source alternatives

## Feedback & Issues

Found a bug or have a feature idea? Email developer-offerings@boomi.com with a clear description, steps to reproduce, and any relevant error messages.

## Installation

```bash
/plugin marketplace add OfficialBoomi/boomi-companion
/plugin install bc-integration@boomi-companion
```

Or browse and install via `/plugin` interactively.

## Commands

| Command | Purpose |
|---------|---------|
| `/bc-integration:env-setup-guide` | Interactive Boomi credentials setup |
| `/bc-integration:configure-template-workspace` | Create a reusable project template |
| `/bc-integration:memory` | Review cross-session memory vault (learnings, stats) |
| `/bc-integration:tidy-up` | Clean development artifacts |

After running `configure-template-workspace`, use `/freshies` from any empty directory to scaffold a new project.

## Credential Handling

**Platform configuration credentials** (`.env` file): Your `.env` stores the Boomi API token, account ID, environment IDs, and other platform config needed by the CLI tools. These are necessary for the agent to push, pull, deploy, and test on your behalf.

**How the agent interacts with `.env`**: The project settings and agent instructions steer the agent away from directly reading your `.env` file. The CLI tools load credentials internally — the agent invokes the tools without seeing the credential values. This is a default convenience buffer, not a hard security boundary. Be aware that:

- The `.env` file is a plaintext file on your machine
- The default deny rules in the template workspace `.claude/settings.json` guide the agent away from common file-reading paths, but a sufficiently motivated or creatively prompted agent could find indirect ways to access file contents

If you need stricter isolation, consider Claude Code's [sandboxing options](https://docs.anthropic.com/en/docs/claude-code/security) or OS-level file permissions.

