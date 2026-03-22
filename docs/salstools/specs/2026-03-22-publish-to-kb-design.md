# Design Spec: publish-to-kb

**Date:** 2026-03-22
**Status:** Draft
**Author:** Claude (brainstormed with ssmith-ms)
**Namespace:** salstools

## Summary

A Claude Code custom slash command (`/publish-to-kb`) that publishes documentation from any project to one of N BookStack knowledge base instances. Uses the `ttpears/bookstack-mcp` MCP server for BookStack API access and a skill file for workflow orchestration — instance selection, content preparation, intelligent placement, and publishing.

## Problem

Project documentation lives in repos but needs to reach team knowledge bases. Today this requires manually copying content into BookStack's web UI, navigating the hierarchy, and formatting it. With multiple teams using separate BookStack instances (currently Bibbeo and Loodon, potentially more), this friction multiplies.

## Goals

- Publish docs to any configured BookStack instance directly from Claude Code
- Support 1-N BookStack instances with a generic, convention-based configuration
- Provide intelligent placement suggestions based on existing KB structure
- Allow project-level defaults to skip repetitive prompts
- Keep secrets secure and out of repos

## Non-Goals (v1)

- Bulk/batch publishing (one page per invocation)
- Syncing or pulling content from BookStack back to project files
- Automatic publishing on commit (potential future hook)
- Creating books/chapters from project information (v2 candidate)
- Publishing to a marketplace (may promote salstools later)

---

## Architecture

### Approach

Dual-layer: **MCP servers** handle the BookStack API, **skill file** handles workflow orchestration.

Each BookStack instance runs its own `ttpears/bookstack-mcp` server process, launched via a shared wrapper script. The skill reads configuration, resolves defaults, manages user interaction, and calls the appropriate MCP server tools by name.

### Component Diagram

```
┌─────────────────────────────────────────────────────┐
│  Claude Code                                        │
│                                                     │
│  ┌─────────────────────┐   ┌──────────────────────┐ │
│  │  /publish-to-kb     │   │  /publish-to-kb      │ │
│  │  (main skill)       │   │  :configure           │ │
│  └────────┬────────────┘   └──────────┬───────────┘ │
│           │                           │             │
│           ▼                           ▼             │
│  ┌─────────────────────────────────────────────────┐ │
│  │  ~/.config/bookstack/.env (instance registry)   │ │
│  │  <project>/.bookstack/defaults.env (defaults)    │ │
│  └────────┬────────────────────────┬──────────────┘ │
│           │                        │                │
│           ▼                        ▼                │
│  ┌────────────────┐     ┌────────────────┐          │
│  │ MCP Server:    │     │ MCP Server:    │   ...N   │
│  │ bookstack-     │     │ bookstack-     │          │
│  │ bibbeo         │     │ loodon         │          │
│  └───────┬────────┘     └───────┬────────┘          │
└──────────┼──────────────────────┼───────────────────┘
           │                      │
           ▼                      ▼
    ┌──────────────┐      ┌──────────────┐
    │ BookStack    │      │ BookStack    │
    │ (Bibbeo)     │      │ (Loodon)     │
    └──────────────┘      └──────────────┘
```

---

## Configuration

### Global Instance Registry

**Location:** `~/.config/bookstack/.env`

Stores credentials for all BookStack instances. One block per instance, using a naming convention that the skill parses dynamically.

```env
# BookStack Instance Registry
# Add one block per instance. <NAME> must be UPPERCASE alphanumeric.
# The skill auto-discovers instances by scanning for BOOKSTACK_<NAME>_BASE_URL keys.

# --- Instance: BIBBEO ---
BOOKSTACK_BIBBEO_BASE_URL=https://kb.bibbeo.com
BOOKSTACK_BIBBEO_TOKEN_ID=your-token-id
BOOKSTACK_BIBBEO_TOKEN_SECRET=your-token-secret
BOOKSTACK_BIBBEO_LABEL=Bibbeo KB

# --- Instance: LOODON ---
BOOKSTACK_LOODON_BASE_URL=https://kb.loodon.com
BOOKSTACK_LOODON_TOKEN_ID=your-token-id
BOOKSTACK_LOODON_TOKEN_SECRET=your-token-secret
BOOKSTACK_LOODON_LABEL=Loodon KB
```

**Security:** File must be `chmod 600`. Contains API secrets — never committed to any repo.

**Adding a new instance:** Add a new block with a unique `<NAME>` prefix, then run `/publish-to-kb:configure` to generate the corresponding MCP server stanza.

### Project-Level Defaults

**Location:** `<project-root>/.bookstack/defaults.env`

Sets defaults for a specific project to skip repetitive prompts. Contains **no secrets** — only an instance name and hierarchy preferences. This file is safe to commit so team members sharing the repo get the same defaults.

```env
# Default instance for this project (matches <NAME> from global registry)
BOOKSTACK_DEFAULT_INSTANCE=BIBBEO

# Optional: default target location (set whichever levels apply)
BOOKSTACK_DEFAULT_SHELF=Infrastructure
BOOKSTACK_DEFAULT_BOOK=Odoo 19.x
BOOKSTACK_DEFAULT_CHAPTER=
```

- If only `BOOKSTACK_DEFAULT_SHELF` is set, the skill starts navigation from that shelf
- If shelf + book are set, it narrows further
- Any unset level triggers interactive "search and suggest" for that level down
- Safe to commit (no secrets). Team members still need their own credentials in `~/.config/bookstack/.env`

### MCP Server Wrapper

**Location:** `~/.config/bookstack/launch.sh`

Sources the global `.env` file and maps instance-specific vars to the generic env vars that `ttpears/bookstack-mcp` expects.

```bash
#!/usr/bin/env bash
# Usage: launch.sh <INSTANCE_NAME>
# Sources ~/.config/bookstack/.env and launches bookstack-mcp
# with the correct credentials for the named instance.

set -euo pipefail

INSTANCE="${1:?Usage: launch.sh <INSTANCE_NAME>}"
ENV_FILE="${HOME}/.config/bookstack/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: $ENV_FILE not found" >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

# Map BOOKSTACK_<INSTANCE>_* to what the MCP server expects
URL_VAR="BOOKSTACK_${INSTANCE}_BASE_URL"
ID_VAR="BOOKSTACK_${INSTANCE}_TOKEN_ID"
SECRET_VAR="BOOKSTACK_${INSTANCE}_TOKEN_SECRET"

export BOOKSTACK_BASE_URL="${!URL_VAR:?$URL_VAR not set in $ENV_FILE}"
export BOOKSTACK_TOKEN_ID="${!ID_VAR:?$ID_VAR not set in $ENV_FILE}"
export BOOKSTACK_TOKEN_SECRET="${!SECRET_VAR:?$SECRET_VAR not set in $ENV_FILE}"
export BOOKSTACK_ENABLE_WRITE="true"

exec npx bookstack-mcp
```

**Security:** File must be `chmod 700`.

### MCP Server Registration

**Mechanism:** `claude mcp add` CLI command (user scope)

One MCP server per instance. Generated by `/publish-to-kb:configure`.

```bash
# Example output from /publish-to-kb:configure:
claude mcp add --transport stdio --scope user bookstack-bibbeo -- "$HOME/.config/bookstack/launch.sh" BIBBEO
claude mcp add --transport stdio --scope user bookstack-loodon -- "$HOME/.config/bookstack/launch.sh" LOODON
```

**Note:** The configure command resolves `$HOME` to an absolute path at generation time to avoid tilde expansion issues in the stored MCP config.

Adding a new instance = add credentials to `~/.config/bookstack/.env` + run `/publish-to-kb:configure` to generate and execute the `claude mcp add` command.

---

## Skill Workflow

### Invocation

```
/publish-to-kb                          # Interactive: prompts for everything
/publish-to-kb loodon                   # Specifies instance, prompts for rest
/publish-to-kb docs/PRD.md             # Specifies content file, prompts for rest
/publish-to-kb loodon docs/PRD.md      # Specifies both
```

### Step 1 — Resolve Instance

1. Check invocation args for explicit instance name
2. If not provided, check `<project>/.bookstack/defaults.env` for `BOOKSTACK_DEFAULT_INSTANCE`
3. If no default, parse `~/.config/bookstack/.env` to discover all instances (scan for `BOOKSTACK_<NAME>_BASE_URL` keys)
4. Present numbered list with labels: "Which KB? (1) Bibbeo KB (2) Loodon KB"
5. User picks

The resolved instance name determines which MCP server tools to call: `mcp__bookstack_<lowercase_name>__<tool>`.

### Step 2 — Resolve Content

Three modes, determined by what the user provides:

**File path given** — Read the file, use markdown content as-is. Present a preview and confirm before publishing.

**Description given** — Claude writes the documentation, presents the draft for user approval. User can request edits before proceeding.

**"Synthesize from project"** — Claude reads relevant project files (scripts, configs, existing docs, comments), drafts a KB article using project context. Presents for approval. Optionally uses a template from `~/.claude/commands/publish-to-kb/templates/` as a scaffold.

In all cases: **user sees and approves final content before it's pushed.**

### Step 3 — Resolve Placement

1. Start from project defaults (shelf → book → chapter) if set
2. For any unresolved level, use MCP search tools to query existing BookStack structure:
   - `mcp__bookstack_<name>__get_shelves` — list available shelves
   - `mcp__bookstack_<name>__get_books` — list books (optionally filtered by shelf)
   - `mcp__bookstack_<name>__get_chapters` — list chapters in the target book
   - `mcp__bookstack_<name>__search_content` — find existing content that matches the topic
3. Present suggestion: "This looks like it belongs in **Infrastructure → Odoo 19.x → Deployment**. Sound right?"
4. User confirms, picks a different location, or says "create new"
5. If creating new at the **shelf** level: use `mcp__bookstack_<name>__create_shelf`
6. If creating new at the **book** or **chapter** level: the `bookstack-mcp` server does not expose `create_book` or `create_chapter` tools. The skill falls back to the BookStack REST API via `curl` (using credentials from the resolved instance) to create these entities. This is a v1 workaround — if `bookstack-mcp` adds these tools later, the skill should prefer them.

**Fallback:** If the KB is empty or new, skip suggestions and ask the user directly where to place it.

### Step 4 — Publish

1. Check if a page with a matching name already exists in the target location
   - If yes: warn the user, show existing page URL, confirm before overwriting via `mcp__bookstack_<name>__update_page`
   - If no: create via `mcp__bookstack_<name>__create_page`
2. Report back with the published page URL

### Step 5 — Optional: Tag Source

If content came from a project file, optionally note the publication in a comment at the bottom of the source file:

```markdown
<!-- Published to Bibbeo KB: https://kb.bibbeo.com/books/odoo-19x/page/deployment-runbook (2026-03-22) -->
```

**Off by default.** Can be enabled via a flag or future configuration.

---

## File Structure

```
~/.config/bookstack/
├── .env                              # Instance registry (secrets, chmod 600)
├── .env.example                      # Shareable template with docs (no secrets)
└── launch.sh                         # MCP wrapper script (chmod 700)

~/.claude/commands/
├── publish-to-kb.md                  # Main skill: full publish workflow
└── publish-to-kb/
    ├── configure.md                  # /publish-to-kb:configure — generate MCP stanzas
    └── templates/
        ├── runbook.md                # Template: deployment runbook
        ├── architecture.md           # Template: architecture doc
        └── blank.md                  # Template: minimal page

<any-project>/
└── .bookstack/
    └── defaults.env                  # Project defaults (committable, no secrets)
```

---

## Configure Sub-Command

`/publish-to-kb:configure` reads `~/.config/bookstack/.env`, discovers all instance blocks, and:

1. Generates `claude mcp add` commands for each instance (resolving `$HOME` to an absolute path)
2. Validates that all required fields are present per instance (`_BASE_URL`, `_TOKEN_ID`, `_TOKEN_SECRET`)
3. Warns if any instance lacks a `_LABEL` (falls back to the instance name)
4. Optionally executes the generated commands with user confirmation

This is the single command needed when adding a new BookStack instance.

---

## Security Considerations

- **Secrets isolation:** All API tokens live in `~/.config/bookstack/.env` (chmod 600), never in project repos or Claude Code settings files
- **No secrets in MCP config:** The wrapper script sources secrets at runtime; the MCP registration only stores the script path and instance name
- **Project defaults contain no secrets:** Only instance name and hierarchy preferences — safe to commit
- **Write operations require confirmation:** User always approves content and placement before publishing
- **Update warnings:** Overwriting existing pages requires explicit confirmation
- **`.env.example` ships without real values:** Safe to share or commit as documentation

---

## Future Considerations (Not In Scope)

- **v2: Book/chapter creation from project info** — Create full BookStack structure (shelves, books, chapters) populated from project documentation
- **Bulk publishing** — Publish multiple files in one invocation
- **Bidirectional sync** — Pull KB content back to project files
- **Commit hook integration** — Auto-publish on specific commits or tags
- **Marketplace publishing** — Promote salstools to a Claude Code plugin/marketplace for sharing
- **Template library expansion** — Community-contributed doc templates

---

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| `ttpears/bookstack-mcp` | latest (npm) | BookStack API via MCP |
| Claude Code | current | Slash commands, MCP server support |
| BookStack | v24.x+ | Target KB instances (API v1) |
| Node.js | 18+ | Required by bookstack-mcp |

---

## Success Criteria

1. User can run `/publish-to-kb` from any project and publish a page to any configured BookStack instance
2. Project defaults skip the instance selection and narrow placement when configured
3. Adding a new BookStack instance requires only: (a) add credentials to `~/.config/bookstack/.env`, (b) run `/publish-to-kb:configure` to register the MCP server
4. Content is always previewed and approved before publishing
5. Existing pages are never silently overwritten
6. No secrets appear in any committed file
