#!/usr/bin/env bash
# Graph loop memory: save, search, and recall cross-session learnings in a
# centralized, Obsidian-compatible markdown vault.
#
# The vault is a plain folder of Markdown notes with [[wikilinks]] — the links
# between notes form a knowledge graph, browsable in Obsidian (free) or any
# open-source reader (Logseq, Foam, SilverBullet) and syncable with git or
# Syncthing. Default location: ~/.boomi-memory. Set BOOMI_MEMORY_VAULT in the
# workspace .env (or environment) to relocate; one vault is shared across all
# projects on the machine.
#
# This tool is local-only: no platform API calls, no credentials required, and
# no load_env — it must work outside a configured workspace. Never store
# credentials, tokens, or account IDs in the vault.
#
# Usage:
#   bash scripts/boomi-memory.sh init
#   bash scripts/boomi-memory.sh save --title "..." --type error-fix [--tags a,b] [--body "..."] [--link "Note"]
#   bash scripts/boomi-memory.sh search <term> [--tag t] [--type t]
#   bash scripts/boomi-memory.sh show <title-or-path>
#   bash scripts/boomi-memory.sh recent [--limit N]
#   bash scripts/boomi-memory.sh stats

source "$(dirname "$0")/boomi-common.sh"

DEFAULT_VAULT="$HOME/.boomi-memory"
VAULT=""   # set by --vault on any subcommand

NOTE_TYPES="learning|error-fix|pattern|preference|environment|project"

usage() {
  cat >&2 <<'EOF'
Graph loop memory — cross-session learnings in an Obsidian-compatible vault.

Usage:
  bash scripts/boomi-memory.sh init
  bash scripts/boomi-memory.sh save --title T [--type learning] [--tags a,b]
                               [--body B] [--body-file F] [--link "Note"]...
                               [--project P]
  bash scripts/boomi-memory.sh search [term] [--tag t] [--type t] [--limit N]
  bash scripts/boomi-memory.sh show <title-or-path>
  bash scripts/boomi-memory.sh recent [--limit N]
  bash scripts/boomi-memory.sh stats

Commands:
  init       Create the vault (learnings/ + hubs/ + README) if absent. Idempotent.
  save       Write a learning note. A save whose title matches an existing note
             appends a dated "## Update" section and merges tags/links instead
             of duplicating. --body may be repeated (blocks joined by a blank
             line); multiline content works via $'line1\nline2'.
  search     Full-text search (case-insensitive; every word must match, order
             free — matches titles, tags, bodies, and [[wikilinks]]), optionally
             narrowed by --tag/--type frontmatter filters.
  show       Print one note, resolved by path, exact title, or filename slug.
  recent     List notes by frontmatter "updated:" (newest first).
  stats      Note counts per type, total wikilinks, and unlinked (orphan) notes
             to consolidate.

Note types: learning | error-fix | pattern | preference | environment | project

Environment:
  BOOMI_MEMORY_VAULT   Vault location. Resolution order: --vault flag, exported
                       variable, workspace ./.env's BOOMI_MEMORY_VAULT, then
                       ~/.boomi-memory (default).
EOF
}

die() {
  echo "ERROR: $1" >&2
  exit 1
}

# --- Vault resolution ---

_vault_dir() {
  if [[ -n "$VAULT" ]]; then
    echo "$VAULT"
  elif [[ -n "${BOOMI_MEMORY_VAULT:-}" ]]; then
    echo "${BOOMI_MEMORY_VAULT/#\~/$HOME}"
  elif [[ -f "./.env" ]]; then
    # Read one optional variable from the workspace .env without sourcing it.
    local v=""
    v=$(grep -E '^[[:space:]]*BOOMI_MEMORY_VAULT=' ./.env | tail -n1 \
        | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
        | sed 's/^"//;s/"$//;s/^'"'"'//;s/'"'"'$//' || true)
    if [[ -n "$v" ]]; then
      echo "${v/#\~/$HOME}"
    else
      echo "$DEFAULT_VAULT"
    fi
  else
    echo "$DEFAULT_VAULT"
  fi
}

_ensure_vault() {
  local vault
  vault="$(_vault_dir)"
  mkdir -p "$vault/learnings" "$vault/hubs"
  if [[ ! -f "$vault/README.md" ]]; then
    cat > "$vault/README.md" <<'EOF'
# Boomi Graph Loop Memory

Cross-session learnings from Boomi integration work, captured by the
boomi-integration skill via `boomi-memory.sh`.

- Notes are plain Markdown with `[[wikilinks]]` — the links form a knowledge
  graph (search/backlinks included).
- Human browsing: open this folder in Obsidian (free) via "Open folder as
  vault" and turn on the graph view. Open-source readers of the same format:
  Logseq, Foam (VS Code), SilverBullet.
- Sharing across machines/teammates: sync this folder with git or Syncthing
  (both free and open source). Do not push this vault to a public repo.
- Never store credentials, tokens, or account IDs here.

Reference: `references/guides/graph_loop_memory.md` in the boomi-integration
skill. Commands: `bash <skill-path>/scripts/boomi-memory.sh --help`.
EOF
  fi
  echo "$vault"
}

# --- Note helpers ---

# Lowercase filename slug: "Map functions: chaining" -> "map-functions-chaining"
_slugify() {
  local s
  s=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | cut -c1-80 \
      | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  echo "$s"
}

# YAML double-quoted scalar
_yaml_quote() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  echo "\"$s\""
}

# Value of a frontmatter key (line "key: value" between the --- fences)
_fm_value() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  [[ "$(head -n1 "$file")" == "---" ]] || return 0
  sed -n '2,/^---/p' "$file" | sed -n "s/^${key}:[[:space:]]*//p" | head -n1
}

# Frontmatter title with surrounding quotes stripped
_fm_title() {
  _fm_value "$1" title | sed 's/^"//;s/"$//'
}

# Print the path of the note whose frontmatter title is exactly $1, else fail.
_find_by_title() {
  local title="$1" vault="$2" f
  local needle="title: $(_yaml_quote "$title")"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if grep -qxF -- "$needle" "$f"; then
      echo "$f"
      return 0
    fi
  done < <(find "$vault" -type f -name '*.md' | sort)
  return 1
}

# Normalize one or more comma-separated tag lists into a deduped "a, b" string.
# Tags are lowercased; internal spaces become dashes; anything outside
# [a-z0-9-] drops.
_normalize_tags() {
  local seen=" " out="" list tok
  local -a parts=() tags=()
  for list in "$@"; do
    IFS=',' read -ra parts <<< "$list"
    [[ ${#parts[@]} -eq 0 ]] && continue
    for tok in "${parts[@]}"; do
      tok=$(printf '%s' "$tok" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:space:]' '-')
      tok=$(printf '%s' "$tok" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]//g')
      [[ -z "$tok" ]] && continue
      [[ "$seen" == *" $tok "* ]] && continue
      seen+="$tok "
      tags+=("$tok")
    done
  done
  if [[ ${#tags[@]} -gt 0 ]]; then
    local IFS=','
    out="${tags[*]}"
  fi
  echo "$out" | sed 's/,/, /g'
}

# True if the note carries tag $2 (both sides normalized the same way)
_note_has_tag() {
  local ft needle
  ft=$(_fm_value "$1" tags)
  ft=$(printf '%s' "$ft" | tr -d '[]' | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
  needle=$(printf '%s' "$2" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:space:]' '-' | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]//g')
  [[ -n "$needle" && ",${ft}," == *",${needle},"* ]]
}

# Add "- [[target]]" under "## Linked Notes" of $1, creating the section if
# needed. Appends a backlink so links resolve in both directions in plain grep.
_append_backlink() {
  local file="$1" from_title="$2"
  local line="- [[${from_title}]]"
  grep -qF -- "$line" "$file" && return 0
  _append_section_item "$file" "Linked Notes" "$line"
}

# Append $3 as a list item directly under section "## $2" in file $1
# (creating the section at the end if absent). Idempotent per line.
_append_section_item() {
  local file="$1" header="$2" line="$3"
  grep -qF -- "$line" "$file" && return 0
  if grep -q "^## ${header}\$" "$file"; then
    local tmp="${file}.tmp"
    awk -v hdr="^## ${header}\$" -v item="$line" '
      $0 ~ hdr && !done { print; print item; done = 1; next }
      { print }
    ' "$file" > "$tmp" && mv "$tmp" "$file"
  else
    printf '\n## %s\n%s\n' "$header" "$line" >> "$file"
  fi
}

_vault_notes() {
  # All notes, README excluded, sorted for stable output
  find "$1" -type f -name '*.md' ! -name 'README.md' | sort
}

# --- Commands ---

cmd_init() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --vault)  VAULT="$2"; shift 2 ;;
      -h|--help) echo "Usage: bash scripts/boomi-memory.sh init [--vault PATH]"; exit 0 ;;
      *)        die "Unknown option for init: $1" ;;
    esac
  done
  local vault
  vault="$(_ensure_vault)"
  echo "Memory vault ready: ${vault}"
  echo "  Notes land in ${vault}/learnings/; hub/index notes in ${vault}/hubs/."
  echo "  Relocate by setting BOOMI_MEMORY_VAULT in .env or the environment."
}

cmd_save() {
  local title="" type="learning" tags="" body="" body_file="" project=""
  local -a links=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title)     title="$2"; shift 2 ;;
      --type)      type="$2"; shift 2 ;;
      --tags)      tags="$2"; shift 2 ;;
      --body)      [[ -n "$body" ]] && body+=$'\n\n'; body+="$2"; shift 2 ;;
      --body-file) body_file="$2"; shift 2 ;;
      --link)      links+=("$2"); shift 2 ;;
      --project)   project="$2"; shift 2 ;;
      --vault)     VAULT="$2"; shift 2 ;;
      -h|--help)   usage; exit 0 ;;
      *)           die "Unknown option for save: $1" ;;
    esac
  done

  [[ -n "$title" ]] || die "--title is required"
  case "$type" in
    learning|error-fix|pattern|preference|environment|project) ;;
    *) die "invalid --type '${type}' — use one of: ${NOTE_TYPES}" ;;
  esac
  if [[ -n "$body_file" ]]; then
    [[ -f "$body_file" ]] || die "--body-file not found: ${body_file}"
    local file_body
    file_body=$(cat "$body_file")
    [[ -n "$body" ]] && body+=$'\n\n'
    body+="$file_body"
  fi
  [[ -n "$body" ]] || die "--body (or --body-file) is required — a note without content is not memorable"

  local vault now today existing file slug i link target_file note_file r ref_title
  vault="$(_ensure_vault)"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  today="$(date -u +%Y-%m-%d)"
  [[ -n "$project" ]] || project="$(basename "$(pwd)")"
  tags="$(_normalize_tags "$tags")"

  # Same title -> append a dated update instead of duplicating
  existing="$(_find_by_title "$title" "$vault" || true)"
  if [[ -n "$existing" ]]; then
    note_file="$existing"
    {
      printf '\n## Update — %s\n\n' "$today"
      printf '%s\n' "$body"
    } >> "$existing"
    sedi -E "s/^updated:.*/updated: ${now}/" "$existing"
    if [[ -n "$tags" ]]; then
      local old_tags merged
      old_tags=$(_fm_value "$existing" tags | tr -d '[]')
      merged=$(_normalize_tags "$old_tags" "$tags")
      [[ -n "$merged" ]] && sedi -E "s/^tags:.*/tags: [${merged}]/" "$existing"
    fi
    if [[ ${#links[@]} -gt 0 ]]; then
      for link in "${links[@]}"; do
        _append_section_item "$existing" "Links" "- [[${link}]]"
      done
    fi
    echo "Updated existing note: ${existing}"
    echo "  Appended '## Update — ${today}', merged tags and links."
  else
    slug="$(_slugify "$title")"
    [[ -n "$slug" ]] || slug="note"
    file="${vault}/learnings/${slug}.md"
    i=2
    while [[ -f "$file" ]]; do
      file="${vault}/learnings/${slug}-${i}.md"
      i=$((i + 1))
    done
    note_file="$file"
    {
      printf -- '---\n'
      printf 'title: %s\n' "$(_yaml_quote "$title")"
      printf 'type: %s\n' "$type"
      printf 'tags: [%s]\n' "$tags"
      printf 'project: %s\n' "$(_yaml_quote "$project")"
      printf 'created: %s\n' "$now"
      printf 'updated: %s\n' "$now"
      printf -- '---\n\n'
      printf '%s\n' "$body"
      if [[ ${#links[@]} -gt 0 ]]; then
        printf '\n## Links\n'
        for link in "${links[@]}"; do
          printf -- '- [[%s]]\n' "$link"
        done
      fi
    } > "$file"
    echo "Saved: ${file}"
    echo "  type: ${type}, tags: [${tags}], project: ${project}"
  fi

  # Backlink each linked note so the graph resolves in both directions
  if [[ ${#links[@]} -gt 0 ]]; then
    for link in "${links[@]}"; do
      target_file="$(_find_by_title "$link" "$vault" || true)"
      [[ -n "$target_file" ]] || continue
      _append_backlink "$target_file" "$title"
    done
  fi

  # Backfill: list notes that already reference this one under Linked Notes
  while IFS= read -r r; do
    [[ -z "$r" || "$r" == "$note_file" ]] && continue
    if grep -qF -- "[[${title}]]" "$r"; then
      ref_title=$(_fm_title "$r")
      [[ -n "$ref_title" ]] && _append_section_item "$note_file" "Linked Notes" "- [[${ref_title}]]"
    fi
  done < <(_vault_notes "$vault")
  return 0
}

cmd_search() {
  local term="" tag="" type="" limit=25
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tag)   tag="$2"; shift 2 ;;
      --type)  type="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      --vault) VAULT="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *)       [[ -n "$term" ]] && term+=" "; term+="$1"; shift ;;
    esac
  done
  [[ -n "$term" || -n "$tag" || -n "$type" ]] || die "give a search term, --tag, or --type (or use 'recent')"

  local vault
  vault="$(_vault_dir)"
  [[ -d "$vault" ]] || die "no memory vault at ${vault} — run 'boomi-memory.sh init' first"

  local matched first_word word f
  matched=$(_vault_notes "$vault")
  [[ -n "$matched" ]] || { echo "0 notes in vault (${vault}) — capture some with 'save'."; exit 0; }

  first_word=""
  if [[ -n "$term" ]]; then
    term=$(printf '%s' "$term" | tr -s '[:space:]' ' ')
    # Every word must appear (order-free): intersect per-word match sets
    local -a words=()
    IFS=' ' read -ra words <<< "$term"
    if [[ ${#words[@]} -eq 0 || ( ${#words[@]} -eq 1 && -z "${words[0]}" ) ]]; then
      term=""
    else
      first_word="${words[0]}"
      for word in "${words[@]}"; do
        local next=""
        while IFS= read -r f; do
          [[ -z "$f" ]] && continue
          if grep -IqiF -- "$word" "$f"; then
            next+="${f}"$'\n'
          fi
        done <<< "$matched"
        matched="$next"
        [[ -n "$matched" ]] || break
      done
    fi
  fi
  if [[ -n "$tag" ]]; then
    local next=""
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      if _note_has_tag "$f" "$tag"; then
        next+="${f}"$'\n'
      fi
    done <<< "$matched"
    matched="$next"
  fi
  if [[ -n "$type" ]]; then
    local next=""
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      if [[ "$(_fm_value "$f" type | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "$type" | tr '[:upper:]' '[:lower:]')" ]]; then
        next+="${f}"$'\n'
      fi
    done <<< "$matched"
    matched="$next"
  fi

  local count=0 excerpt=""
  local -a hits=()
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    hits+=("$f")
  done <<< "$matched"
  count=${#hits[@]}
  if [[ "$count" -eq 0 ]]; then
    echo "0 notes matched in ${vault}."
    echo "Nothing memorized on this yet — capture it once you learn it ('save')."
    exit 0
  fi
  echo "${count} note(s) in ${vault}:"
  if [[ "$count" -gt "$limit" ]]; then
    echo "  (showing first ${limit} — narrow the term or filter by --tag/--type)"
  fi
  local shown=0 relpath
  for f in "${hits[@]}"; do
    if [[ "$shown" -ge "$limit" ]]; then break; fi
    shown=$((shown + 1))
    excerpt=""
    if [[ -n "$first_word" ]]; then
      # Skip frontmatter (fence counting) so the excerpt shows body content
      excerpt=$(awk -v w="$first_word" \
        'f==2 && index(tolower($0), tolower(w)) {print; exit} /^---$/ {f++}' \
        "$f" | cut -c1-100)
    fi
    relpath="${f#${vault}/}"
    echo "- ${relpath}"
    echo "    [$(_fm_value "$f" type | sed 's/^"//;s/"$//') · $(_fm_value "$f" updated)] $(_fm_title "$f")"
    if [[ -n "$excerpt" ]]; then
      echo "    ${excerpt}"
    fi
  done
  return 0
}

cmd_show() {
  local target="${1:-}"
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --vault) VAULT="$2"; shift 2 ;;
      *)       die "Unknown option for show: $1" ;;
    esac
  done
  [[ -n "$target" ]] || die "show needs a note title or path"

  local vault f
  vault="$(_vault_dir)"
  if [[ -f "$target" ]]; then
    cat "$target"
    return 0
  fi
  f="$(_find_by_title "$target" "$vault" || true)"
  if [[ -z "$f" ]]; then
    f="${vault}/learnings/$(_slugify "$target").md"
    [[ -f "$f" ]] || f=""
  fi
  [[ -n "$f" && -f "$f" ]] || die "no note titled '${target}' — try 'search' or 'recent'"
  cat "$f"
}

cmd_recent() {
  local limit=10
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      --vault) VAULT="$2"; shift 2 ;;
      -h|--help) echo "Usage: bash scripts/boomi-memory.sh recent [--limit N]"; exit 0 ;;
      *)        die "Unknown option for recent: $1" ;;
    esac
  done
  local vault
  vault="$(_vault_dir)"
  [[ -d "$vault" ]] || die "no memory vault at ${vault} — run 'boomi-memory.sh init' first"

  local files
  files=$(_vault_notes "$vault")
  [[ -n "$files" ]] || { echo "0 notes in vault (${vault}) — capture some with 'save'."; exit 0; }

  # Sort by frontmatter "updated:" (ISO timestamps sort lexicographically)
  local f relpath
  while IFS= read -r f; do
    printf '%s\t%s\n' "$(_fm_value "$f" updated)" "$f"
  done <<< "$files" | sort -r | head -n "$limit" | while IFS=$'\t' read -r _ts f; do
    relpath="${f#${vault}/}"
    echo "- $(_fm_title "$f")  [$(_fm_value "$f" type)]  ${relpath}"
  done
}

cmd_stats() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --vault) VAULT="$2"; shift 2 ;;
      -h|--help) echo "Usage: bash scripts/boomi-memory.sh stats"; exit 0 ;;
      *)        die "Unknown option for stats: $1" ;;
    esac
  done
  local vault
  vault="$(_vault_dir)"
  [[ -d "$vault" ]] || die "no memory vault at ${vault} — run 'boomi-memory.sh init' first"

  local files f t title orphans="" total link_count=0
  files=$(_vault_notes "$vault")
  total=$(printf '%s' "$files" | grep -c . || true)

  echo "Memory vault: ${vault}"
  echo "Notes: ${total}"

  if [[ "$total" -eq 0 ]]; then
    echo "No learnings captured yet — start with 'boomi-memory.sh save'."
    return 0
  fi

  echo "Notes per type:"
  local type_list="learning error-fix pattern preference environment project"
  local n
  for t in $type_list; do
    n=0
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      [[ "$(_fm_value "$f" type)" == "$t" ]] && n=$((n + 1))
    done <<< "$files"
    [[ "$n" -gt 0 ]] && echo "  ${t}: ${n}"
  done

  local c
  link_count=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    c=$(grep -o '\[\[' "$f" | wc -l || true)
    link_count=$((link_count + c))
  done <<< "$files"
  echo "Wikilinks total: ${link_count}"

  # Orphans: no outbound [[link]] and no other note references the title
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    grep -q '\[\[' "$f" && continue
    title=$(_fm_title "$f")
    [[ -z "$title" ]] && continue
    if ! grep -rqF --include='*.md' -- "[[${title}]]" "$vault"; then
      orphans+="${f}"$'\n'
    fi
  done <<< "$files"
  n=$(printf '%s' "$orphans" | grep -c . || true)
  echo "Unlinked notes (no links in or out): ${n}"
  if [[ "$n" -gt 0 ]]; then
    echo "  Consolidate by linking them into related notes or a hub in hubs/:"
    local shown=0 relpath
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      [[ "$shown" -ge 10 ]] && break
      shown=$((shown + 1))
      relpath="${f#${vault}/}"
      echo "    - $(_fm_title "$f")  (${relpath})"
    done <<< "$orphans"
  fi
}

# --- Dispatch ---

cmd="${1:-}"
case "$cmd" in
  -h|--help|"") usage; exit 0 ;;
esac
shift

case "$cmd" in
  init)   cmd_init "$@" ;;
  save)   cmd_save "$@" ;;
  search) cmd_search "$@" ;;
  show)   cmd_show "$@" ;;
  recent) cmd_recent "$@" ;;
  stats)  cmd_stats "$@" ;;
  *)      echo "ERROR: Unknown command: ${cmd}" >&2; usage; exit 1 ;;
esac
