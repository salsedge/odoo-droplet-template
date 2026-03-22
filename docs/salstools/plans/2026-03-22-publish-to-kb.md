# publish-to-kb Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code slash command (`/publish-to-kb`) that publishes documentation to 1-N BookStack instances via MCP.

**Architecture:** Config layer (`~/.config/bookstack/`) holds credentials and a wrapper script that launches per-instance MCP servers. Skill files (`~/.claude/commands/`) orchestrate the workflow — instance selection, content prep, placement, publishing. Project-level defaults (`.bookstack/defaults.env`) allow skipping prompts.

**Tech Stack:** Bash (wrapper script), Markdown (Claude Code custom commands), `ttpears/bookstack-mcp` (npm, MCP server), BookStack REST API (curl fallback for book/chapter creation)

**Spec:** `docs/salstools/specs/2026-03-22-publish-to-kb-design.md`

---

## File Map

```
Files to CREATE:

~/.config/bookstack/
├── .env.example                      # Template with docs, no real secrets
└── launch.sh                         # MCP wrapper: sources .env, maps vars, launches bookstack-mcp

~/.claude/commands/
├── publish-to-kb.md                  # Main slash command: full publish workflow
└── publish-to-kb/
    ├── configure.md                  # Sub-command: discover instances, generate claude mcp add commands
    └── templates/
        ├── runbook.md                # Scaffold: deployment runbook
        ├── architecture.md           # Scaffold: architecture overview doc
        └── blank.md                  # Scaffold: minimal page with title/summary

No files to MODIFY (greenfield).
```

---

## Task 1: Config Directory and .env.example

**Files:**
- Create: `~/.config/bookstack/.env.example`

This is the shareable template that documents the env var convention. No secrets.

- [ ] **Step 1: Create the config directory**

```bash
mkdir -p ~/.config/bookstack
```

- [ ] **Step 2: Write .env.example**

Create `~/.config/bookstack/.env.example` with the full template including:
- Header comment explaining the naming convention (`BOOKSTACK_<NAME>_*`)
- How the skill auto-discovers instances (scans for `_BASE_URL` keys)
- Two example instance blocks (INSTANCE_ONE, INSTANCE_TWO) with placeholder values
- Note about `_LABEL` being optional (falls back to instance name)
- Warning about chmod 600 for the real `.env`
- Password rules block per project convention (see `feedback_env_password_rules.md`)

```env
# BookStack Instance Registry
# ===========================
# One block per BookStack instance. The skill auto-discovers instances
# by scanning for BOOKSTACK_<NAME>_BASE_URL keys.
#
# <NAME> must be UPPERCASE alphanumeric (e.g., BIBBEO, LOODON, ACME).
#
# To create your real config:
#   cp ~/.config/bookstack/.env.example ~/.config/bookstack/.env
#   chmod 600 ~/.config/bookstack/.env
#   # Edit with vi to add real credentials
#
# PASSWORD RULES:
#   - Do NOT use $ (triggers variable interpolation) or backticks
#   - Do NOT wrap values in quotes (quotes are treated as literal characters)
#   - Safe special chars: ! ^ * % & # @

# --- Instance: INSTANCE_ONE ---
BOOKSTACK_INSTANCE_ONE_BASE_URL=https://kb.example.com
BOOKSTACK_INSTANCE_ONE_TOKEN_ID=your-token-id-here
BOOKSTACK_INSTANCE_ONE_TOKEN_SECRET=your-token-secret-here
BOOKSTACK_INSTANCE_ONE_LABEL=Example KB

# --- Instance: INSTANCE_TWO ---
BOOKSTACK_INSTANCE_TWO_BASE_URL=https://kb2.example.com
BOOKSTACK_INSTANCE_TWO_TOKEN_ID=your-token-id-here
BOOKSTACK_INSTANCE_TWO_TOKEN_SECRET=your-token-secret-here
BOOKSTACK_INSTANCE_TWO_LABEL=Second KB
```

- [ ] **Step 3: Verify file exists and is readable**

```bash
cat ~/.config/bookstack/.env.example
```

Expected: Full template content displayed.

- [ ] **Step 4: Commit**

```bash
# This file lives outside the repo, so no git commit.
# Verify it's in place:
ls -la ~/.config/bookstack/.env.example
```

---

## Task 2: MCP Wrapper Script (launch.sh)

**Files:**
- Create: `~/.config/bookstack/launch.sh`

The wrapper sources `~/.config/bookstack/.env`, maps `BOOKSTACK_<NAME>_*` vars to what `bookstack-mcp` expects, and launches the MCP server.

- [ ] **Step 1: Write the test .env for validation**

Create a temporary test env file to verify the wrapper logic:

```bash
cat > /tmp/bookstack-launch-test.env << 'EOF'
BOOKSTACK_TESTINST_BASE_URL=https://test.example.com
BOOKSTACK_TESTINST_TOKEN_ID=test-id-123
BOOKSTACK_TESTINST_TOKEN_SECRET=test-secret-456
BOOKSTACK_TESTINST_LABEL=Test Instance
EOF
```

- [ ] **Step 2: Write launch.sh**

Create `~/.config/bookstack/launch.sh`:

```bash
#!/usr/bin/env bash
# launch.sh — MCP wrapper for bookstack-mcp
# Usage: launch.sh <INSTANCE_NAME>
#
# Sources ~/.config/bookstack/.env and launches bookstack-mcp
# with the correct credentials for the named instance.
#
# Part of salstools/publish-to-kb.
# See: docs/salstools/specs/2026-03-22-publish-to-kb-design.md

set -euo pipefail

INSTANCE="${1:?Usage: launch.sh <INSTANCE_NAME>}"
ENV_FILE="${ENV_FILE:-${HOME}/.config/bookstack/.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: $ENV_FILE not found. Copy .env.example and add your credentials:" >&2
  echo "  cp ${ENV_FILE}.example ${ENV_FILE}" >&2
  echo "  chmod 600 ${ENV_FILE}" >&2
  exit 1
fi

# Source all vars from the env file
set -a
source "$ENV_FILE"
set +a

# Map BOOKSTACK_<INSTANCE>_* to what bookstack-mcp expects
URL_VAR="BOOKSTACK_${INSTANCE}_BASE_URL"
ID_VAR="BOOKSTACK_${INSTANCE}_TOKEN_ID"
SECRET_VAR="BOOKSTACK_${INSTANCE}_TOKEN_SECRET"

export BOOKSTACK_BASE_URL="${!URL_VAR:?Instance '${INSTANCE}' not found — ${URL_VAR} not set in ${ENV_FILE}}"
export BOOKSTACK_TOKEN_ID="${!ID_VAR:?${ID_VAR} not set in ${ENV_FILE}}"
export BOOKSTACK_TOKEN_SECRET="${!SECRET_VAR:?${SECRET_VAR} not set in ${ENV_FILE}}"
export BOOKSTACK_ENABLE_WRITE="true"

exec npx bookstack-mcp
```

- [ ] **Step 3: Set permissions**

```bash
chmod 700 ~/.config/bookstack/launch.sh
```

- [ ] **Step 4: Test var mapping (dry run)**

Verify the wrapper's core logic — sourcing the env file and mapping instance-specific vars. This tests the mapping in isolation without launching the MCP server:

```bash
(
  INSTANCE="TESTINST"
  ENV_FILE="/tmp/bookstack-launch-test.env"
  set -a; source "$ENV_FILE"; set +a
  URL_VAR="BOOKSTACK_${INSTANCE}_BASE_URL"
  ID_VAR="BOOKSTACK_${INSTANCE}_TOKEN_ID"
  SECRET_VAR="BOOKSTACK_${INSTANCE}_TOKEN_SECRET"
  echo "BASE_URL=${!URL_VAR}"
  echo "TOKEN_ID=${!ID_VAR}"
  echo "TOKEN_SECRET=${!SECRET_VAR}"
)
```

Expected output:
```
BASE_URL=https://test.example.com
TOKEN_ID=test-id-123
TOKEN_SECRET=test-secret-456
```

- [ ] **Step 5: Test error case — missing instance**

```bash
(
  INSTANCE="NONEXISTENT"
  ENV_FILE="/tmp/bookstack-launch-test.env"
  set -a; source "$ENV_FILE"; set +a
  URL_VAR="BOOKSTACK_${INSTANCE}_BASE_URL"
  echo "${!URL_VAR:?Instance '${INSTANCE}' not found}" 2>&1
) 2>&1
```

Expected: Error message containing "Instance 'NONEXISTENT' not found"

- [ ] **Step 6: Test error case — missing .env file**

Since `launch.sh` now respects `ENV_FILE` as an environment variable override (via `${ENV_FILE:-...}` syntax), this test works by pointing it at a nonexistent path:

```bash
ENV_FILE="/tmp/nonexistent-file.env" bash ~/.config/bookstack/launch.sh TESTINST 2>&1; echo "EXIT: $?"
```

Expected: Error message about .env not found with copy instructions. `EXIT: 1`.

- [ ] **Step 7: Clean up test fixtures**

```bash
rm /tmp/bookstack-launch-test.env
```

---

## Task 3: Configure Sub-Command

**Files:**
- Create: `~/.claude/commands/publish-to-kb/configure.md`

This sub-command reads the global `.env`, discovers instances, and generates `claude mcp add` commands.

- [ ] **Step 1: Create the commands directory structure**

```bash
mkdir -p ~/.claude/commands/publish-to-kb/templates
```

- [ ] **Step 2: Write configure.md**

Create `~/.claude/commands/publish-to-kb/configure.md`:

```markdown
---
description: "Discover BookStack instances and register MCP servers"
---

You are running the `/publish-to-kb:configure` sub-command.

## What This Does

Reads `~/.config/bookstack/.env`, discovers all configured BookStack instances, validates them, and generates `claude mcp add` commands to register each instance as an MCP server.

## Steps

1. **Read the global config file** at `~/.config/bookstack/.env`
   - If it doesn't exist, tell the user to create it from the example:
     ```
     cp ~/.config/bookstack/.env.example ~/.config/bookstack/.env
     chmod 600 ~/.config/bookstack/.env
     ```
     Then edit it with vi to add real credentials. Stop here.

2. **Discover instances** by scanning for lines matching `BOOKSTACK_<NAME>_BASE_URL=`.
   Extract each unique `<NAME>`.

3. **Validate each instance** has all required fields:
   - `BOOKSTACK_<NAME>_BASE_URL` (required)
   - `BOOKSTACK_<NAME>_TOKEN_ID` (required)
   - `BOOKSTACK_<NAME>_TOKEN_SECRET` (required)
   - `BOOKSTACK_<NAME>_LABEL` (optional — warn if missing, will fall back to NAME)
   Report any validation errors and stop if critical fields are missing.

4. **Resolve the absolute path** to `launch.sh`:
   ```bash
   LAUNCH_SCRIPT="$(cd ~/.config/bookstack && pwd)/launch.sh"
   ```
   This avoids tilde expansion issues in stored MCP config.

5. **Generate `claude mcp add` commands** for each valid instance:
   ```
   claude mcp add --transport stdio --scope user bookstack-<lowercase_name> -- "<absolute_path>/launch.sh" <NAME>
   ```

6. **Present the commands to the user** with a summary:
   ```
   Found N BookStack instance(s):
     - BIBBEO (Bibbeo KB) → https://kb.bibbeo.com
     - LOODON (Loodon KB) → https://kb.loodon.com

   Commands to register MCP servers:

   claude mcp add --transport stdio --scope user bookstack-bibbeo -- "/Users/you/.config/bookstack/launch.sh" BIBBEO
   claude mcp add --transport stdio --scope user bookstack-loodon -- "/Users/you/.config/bookstack/launch.sh" LOODON
   ```

7. **Ask the user** if they want to run these commands now.
   - If yes: execute each command via Bash and report results.
   - If no: tell them to copy and run manually.

## Important

- Never display or log the actual TOKEN_ID or TOKEN_SECRET values.
- The MCP server name format is `bookstack-<lowercase_name>` (e.g., `bookstack-bibbeo`).
- If an MCP server with that name already exists, warn the user and ask if they want to overwrite.
```

- [ ] **Step 3: Verify the file**

```bash
cat ~/.claude/commands/publish-to-kb/configure.md
```

Expected: Full content displayed with frontmatter.

- [ ] **Step 4: Commit**

No git commit — file lives outside the repo. Verify:

```bash
ls -la ~/.claude/commands/publish-to-kb/configure.md
```

---

## Task 4: Document Templates

**Files:**
- Create: `~/.claude/commands/publish-to-kb/templates/runbook.md`
- Create: `~/.claude/commands/publish-to-kb/templates/architecture.md`
- Create: `~/.claude/commands/publish-to-kb/templates/blank.md`

These are scaffolds Claude uses when synthesizing content. They provide structure, not content.

- [ ] **Step 1: Write blank.md template**

Create `~/.claude/commands/publish-to-kb/templates/blank.md`:

```markdown
# {title}

## Summary

{one-paragraph summary of what this page covers}

## Content

{main content goes here}

---

*Last updated: {date}*
```

- [ ] **Step 2: Write runbook.md template**

Create `~/.claude/commands/publish-to-kb/templates/runbook.md`:

```markdown
# {title} — Runbook

## Overview

{what this runbook covers and when to use it}

## Prerequisites

- {prerequisite 1}
- {prerequisite 2}

## Procedure

### Step 1: {step title}

{step details}

```bash
{commands}
```

### Step 2: {step title}

{step details}

## Verification

{how to verify the procedure completed successfully}

## Rollback

{how to undo if something goes wrong}

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| {symptom} | {cause} | {fix} |

---

*Last updated: {date}*
```

- [ ] **Step 3: Write architecture.md template**

Create `~/.claude/commands/publish-to-kb/templates/architecture.md`:

```markdown
# {title} — Architecture

## Overview

{high-level description of the system}

## Components

### {component name}

- **Purpose:** {what it does}
- **Technology:** {tech stack}
- **Dependencies:** {what it depends on}

## Data Flow

{describe how data moves through the system}

## Infrastructure

| Resource | Type | Purpose |
|----------|------|---------|
| {resource} | {type} | {purpose} |

## Security

{security considerations, access controls, secrets management}

## Decisions

| Decision | Rationale |
|----------|-----------|
| {decision} | {why} |

---

*Last updated: {date}*
```

- [ ] **Step 4: Verify all templates exist**

```bash
ls -la ~/.claude/commands/publish-to-kb/templates/
```

Expected: `blank.md`, `runbook.md`, `architecture.md` all present.

---

## Task 5: Main Slash Command (publish-to-kb.md)

**Files:**
- Create: `~/.claude/commands/publish-to-kb.md`

This is the core skill file — the full orchestration workflow.

- [ ] **Step 1: Write publish-to-kb.md**

Create `~/.claude/commands/publish-to-kb.md`:

```markdown
---
description: "Publish documentation to a BookStack knowledge base"
---

You are running the `/publish-to-kb` command. This publishes a page to one of the user's BookStack knowledge base instances via MCP.

Arguments (all optional): `$ARGUMENTS`
- First arg may be an instance name (e.g., `bibbeo`, `loodon`)
- An arg ending in `.md` is treated as a file path to publish
- Both can be provided: `/publish-to-kb loodon docs/PRD.md`

## Step 1: Resolve Instance

Parse `$ARGUMENTS` for an explicit instance name (case-insensitive).

If no instance specified, check for project defaults:
- Read `<project-root>/.bookstack/defaults.env` if it exists
- Look for `BOOKSTACK_DEFAULT_INSTANCE=<NAME>`

If still no instance, discover available instances:
- Read `~/.config/bookstack/.env`
- Scan for all `BOOKSTACK_<NAME>_BASE_URL` lines to find instance names
- For each instance, check for a `BOOKSTACK_<NAME>_LABEL` value
- Present a numbered list to the user:

> Which BookStack instance?
> 1. Bibbeo KB (BIBBEO)
> 2. Loodon KB (LOODON)

Wait for the user to pick.

The resolved instance name (uppercase) determines the MCP server tools to use.
The MCP server name is `bookstack-<lowercase_name>`.
All MCP tool calls use the pattern: `mcp__bookstack_<lowercase_name>__<tool_name>`

**IMPORTANT:** If the MCP server for the selected instance is not available (tools not found), tell the user to run `/publish-to-kb:configure` first to register it.

## Step 2: Resolve Content

Check `$ARGUMENTS` for a file path (ends in `.md` or another text extension).

**If a file path is given:**
1. Read the file using the Read tool
2. Present a preview (first 30 lines) and the total line count
3. Ask: "Publish this as-is, or should I make changes first?"
4. If changes requested, edit and re-present until approved

**If no file path but the user describes what they want:**
1. Check if a template from `~/.claude/commands/publish-to-kb/templates/` fits:
   - Deployment/operations content → `runbook.md`
   - System design/infrastructure → `architecture.md`
   - General content → `blank.md`
2. Use the template as a scaffold to draft the page
3. Present the full draft to the user
4. Ask: "Ready to publish, or want changes?"
5. Iterate until approved

**If the user says "synthesize" or "from project":**
1. Read relevant project files (README, docs/, scripts/, configs)
2. Draft a KB article summarizing the project state
3. Present and iterate as above

**The user must approve the final content before proceeding.**

## Step 3: Resolve Placement

Determine where in BookStack's hierarchy (Shelf → Book → Chapter → Page) this content should go.

**Start from project defaults** if `.bookstack/defaults.env` exists:
- `BOOKSTACK_DEFAULT_SHELF` → use as starting shelf
- `BOOKSTACK_DEFAULT_BOOK` → use as starting book
- `BOOKSTACK_DEFAULT_CHAPTER` → use as starting chapter

**For any level not set by defaults, search the existing KB structure:**

1. Get available shelves: call `get_shelves` on the resolved MCP server
2. Analyze the content and suggest which shelf fits best
3. Present: "This looks like it belongs on the **{shelf}** shelf. Right?"
4. Once shelf is confirmed, get books in that shelf via `get_books`
5. Suggest the best-fitting book, or offer to create a new one
6. Once book is confirmed, get chapters via `get_chapters`
7. Suggest chapter placement, or offer to create a new one

**If the user says "create new" at any level:**

For **shelves**: use `create_shelf` via the MCP server.

For **books** or **chapters**: the bookstack-mcp server does not expose `create_book` or `create_chapter` tools. Fall back to the BookStack REST API via curl:

To create a book:
```bash
curl -s -X POST "{base_url}/api/books" \
  -H "Authorization: Token {token_id}:{token_secret}" \
  -H "Content-Type: application/json" \
  -d '{"name": "{book_name}", "description": "{description}"}'
```

To create a chapter:
```bash
curl -s -X POST "{base_url}/api/chapters" \
  -H "Authorization: Token {token_id}:{token_secret}" \
  -H "Content-Type: application/json" \
  -d '{"book_id": {book_id}, "name": "{chapter_name}", "description": "{description}"}'
```

Read the credentials for curl from `~/.config/bookstack/.env` using the resolved instance name:
- Base URL: `BOOKSTACK_<NAME>_BASE_URL`
- Token: `BOOKSTACK_<NAME>_TOKEN_ID:BOOKSTACK_<NAME>_TOKEN_SECRET`

**Fallback:** If the KB is empty or newly created, skip suggestions and ask the user directly where to place the page.

## Step 4: Publish

1. **Check for existing page** with the same name in the target location using `search_content` on the MCP server.

2. **If a matching page exists:**
   - Warn the user: "A page named **{name}** already exists at {url}. Overwrite it?"
   - If yes: use `update_page` with the page ID
   - If no: ask for a different page name

3. **If no matching page:**
   - Use `create_page` with:
     - `book_id` or `chapter_id` (from Step 3)
     - `name` (page title — derived from content H1 or asked)
     - `markdown` (the approved content from Step 2)

4. **Report the result:**
   - "Published: **{page title}** → {page URL}"
   - Include the BookStack instance label for clarity

## Step 5: Tag Source (Optional)

If the content was sourced from a project file AND the user has opted in:
- Append an HTML comment to the source file with the publication URL and date
- This is OFF by default — only do this if the user explicitly requests it

## Error Handling

- **MCP server not found:** Tell the user to run `/publish-to-kb:configure`
- **Auth failure (401/403):** Tell the user to check their API token in `~/.config/bookstack/.env`
- **Instance not found in .env:** List available instances and suggest running configure
- **Network error:** Report the error and suggest checking the BookStack URL
- **No .env file:** Point to `.env.example` and give setup instructions

## Security Rules

- NEVER display or log TOKEN_ID or TOKEN_SECRET values
- NEVER include credentials in any output shown to the user
- When using curl fallback, construct the auth header from env vars — never hardcode
- All credential access goes through `~/.config/bookstack/.env` — no other source
```

- [ ] **Step 2: Verify the file**

```bash
cat ~/.claude/commands/publish-to-kb.md | head -5
```

Expected: Frontmatter with `description: "Publish documentation to a BookStack knowledge base"`

- [ ] **Step 3: Verify file structure and frontmatter**

```bash
head -3 ~/.claude/commands/publish-to-kb.md
```

Expected:
```
---
description: "Publish documentation to a BookStack knowledge base"
---
```

Then in a new Claude Code session (or after restart), confirm `/publish-to-kb` appears in slash command autocomplete.

---

## Task 6: End-to-End Verification

This requires a real BookStack instance with API access configured.

- [ ] **Step 0: Verify bookstack-mcp is available**

```bash
npx bookstack-mcp --help 2>&1 || echo "bookstack-mcp not found — it will be auto-installed by npx on first launch.sh invocation"
```

If npx can resolve the package, you're good. If not (e.g., network issues, registry problems), install it explicitly:

```bash
npm install -g bookstack-mcp
```

- [ ] **Step 1: Create the real .env from the example**

```bash
cp ~/.config/bookstack/.env.example ~/.config/bookstack/.env
chmod 600 ~/.config/bookstack/.env
```

Edit with vi to add real credentials for at least one BookStack instance.

- [ ] **Step 2: Run /publish-to-kb:configure**

In Claude Code, run `/publish-to-kb:configure`. Verify it:
- Discovers the configured instance(s)
- Shows the correct `claude mcp add` commands with absolute paths
- Successfully registers the MCP server(s) when confirmed

- [ ] **Step 3: Restart Claude Code**

MCP servers require a session restart to take effect.

- [ ] **Step 4: Test /publish-to-kb with a simple page**

Run `/publish-to-kb` and:
1. Select an instance (or let it use the default)
2. Describe a test page: "Create a test page with the title 'publish-to-kb test' and a paragraph of lorem ipsum"
3. Approve the content
4. Confirm the placement location
5. Verify the page appears in BookStack at the expected URL

- [ ] **Step 5: Test updating the same page**

Run `/publish-to-kb` again targeting the same page title. Verify:
- The skill detects the existing page
- Warns before overwriting
- Updates successfully when confirmed

- [ ] **Step 6: Test with a file path**

Create a test markdown file and publish it:

```bash
echo "# Test Doc\n\nThis is a test publish from a file." > /tmp/test-publish.md
```

Run `/publish-to-kb /tmp/test-publish.md` and verify:
- Content is read from the file
- Preview is shown
- Publishes successfully

- [ ] **Step 7: Clean up test pages**

Delete the test pages from BookStack via the web UI.

---

## Task 7: Project Defaults for This Repo (Optional)

**Files:**
- Create: `.bookstack/defaults.env` (in the current project)

This is optional — only do this if the user wants to set up defaults for the Odoo project.

- [ ] **Step 1: Create .bookstack directory**

```bash
mkdir -p .bookstack
```

- [ ] **Step 2: Write .gitignore for the .bookstack directory**

Create `.bookstack/.gitignore` to protect against accidentally committing a local `.env` with secrets:

```
# Ignore local overrides with secrets, track defaults
.env
!defaults.env
```

- [ ] **Step 3: Write defaults.env**

Create `.bookstack/defaults.env` with the appropriate defaults:

```env
# BookStack project defaults for odoo-19.x-build
# Instance name must match a block in ~/.config/bookstack/.env
BOOKSTACK_DEFAULT_INSTANCE=BIBBEO

# Target location in BookStack (set whichever levels apply)
BOOKSTACK_DEFAULT_SHELF=Infrastructure
BOOKSTACK_DEFAULT_BOOK=
BOOKSTACK_DEFAULT_CHAPTER=
```

- [ ] **Step 4: Commit**

```bash
git add .bookstack/.gitignore .bookstack/defaults.env
git commit -m "feat(salstools): add BookStack project defaults for publish-to-kb"
```
