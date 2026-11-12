---
description: Review the graph loop memory vault — recent learnings, stats, and unlinked notes
allowed-tools: Bash
---

Review the user's cross-session Boomi memory vault (the centralized learnings from all their Boomi projects) and give them a human-readable summary.

## Steps

1. Load the `boomi-integration` skill and resolve `<skill-path>` (strip the trailing `/SKILL.md` from the skill base directory).

2. Gather the vault state:

```bash
bash <skill-path>/scripts/boomi-memory.sh stats
bash <skill-path>/scripts/boomi-memory.sh recent --limit 10
```

3. If `stats` reports unlinked notes, read a few with `bash <skill-path>/scripts/boomi-memory.sh show "<title>"` and think about what each relates to.

4. Summarize for the user:
   - Vault location, total notes, notes per type
   - The most recent learnings — title plus a one-line gist of each
   - Unlinked notes, if any — offer to consolidate them (link them into related notes or author a hub note under `hubs/`)
   - Remind them how to browse the graph: open the vault folder in Obsidian ("Open folder as vault") for the graph view, and that the folder syncs across machines with git or Syncthing
   - Remind them the vault must never contain credentials, tokens, or account IDs

5. Ask if they want to add a new memory by hand, consolidate the unlinked notes, or relocate the vault (`BOOMI_MEMORY_VAULT` in `.env`). Only write to the vault with their approval during this review.

## Notes

- This command is read-oriented: the agent already captures learnings automatically during normal work (see the skill's `references/guides/graph_loop_memory.md`).
- If the vault does not exist yet, say so plainly and offer `bash <skill-path>/scripts/boomi-memory.sh init` — the first `save` would also create it.
