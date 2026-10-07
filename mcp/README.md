# MCP servers used by this workflow

This setup's `probe` role needs a way to drive a real browser. Everything else in the workflow (planning, building, reviewing) works with Claude Code's built-in tools alone; the servers below are the ones worth adding, not a complete catalog.

**Each MCP server you enable adds its whole tool list to every session's context, whether that session uses it or not.** Enable only the ones you actually use; this matters most on a tightly capped plan (see README.md's "On the cheapest plan").

## Browser automation (for the `probe` role)

**What it's for:** scripted navigation, clicking, form filling, console/network reading, and screenshots, so a `probe` teammate can check a running app under real conditions instead of the orchestrator doing it (see the `browser-testing-via-subagents` lesson: screenshots and click transcripts stay out of the main session's context).

**Options:**
- If you use Claude Code's own Chrome extension integration, the browser tools are already available to any session without separate MCP install; skip this section and just make sure the `probe` role's briefs name the exact URL, persona, and assertions.
- Otherwise, install a general-purpose browser automation MCP server (for example, a Playwright-based one) and point a `probe` teammate at it.

**Install (Playwright-based example):**

```bash
# macOS / Linux
npm install -g @playwright/mcp
npx playwright install chromium

# Windows (PowerShell)
npm install -g @playwright/mcp
npx playwright install chromium
```

**Config snippet** (see `mcp.json.example` in this folder):

```json
{
  "mcpServers": {
    "browser": {
      "command": "npx",
      "args": ["@playwright/mcp"]
    }
  }
}
```

**Required secrets:** none for the server itself. If a `probe` needs to log in to the app under test, pass the login persona and credentials through the task prompt or a local, gitignored env file, never through this config file.

**Verify it works:** start a session, ask it to open a known URL (for example the project's own `localhost` dev server) and read the page title back. A working server returns the title; a broken one errors on the first navigate call.

**Rules the workflow expects from whoever drives it (`probe` role):**
- Record the process id of any browser you launch yourself, and close only that process tree at the end; never close a browser by image name, which can close the owner's own windows too (`probe-chrome-kill-by-pid` lesson).
- Reuse an already-running browser context where the harness supports it, rather than launching a fresh one per check.

## GitHub (optional, read-only use)

**What it's for:** reading issue, PR, and CI status without shelling out to a CLI. This workflow still requires that all GitHub WRITES happen from the main session only, after the owner's go-ahead (see `~/.claude/CLAUDE.md`); an MCP server here is for READS (checking a PR's current state, CI status) when that is more convenient than the CLI.

Check the current package name and maintenance status before installing: MCP server packages for GitHub have moved or been renamed before, so confirm the install command below still resolves to an actively maintained package rather than assuming it.

**Install:**

```bash
npm install -g @modelcontextprotocol/server-github
```

**Config snippet:**

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "<your token, in a local env file, never committed>"
      }
    }
  }
}
```

**Required secrets:** a personal access token with read access to the repos you use it on. Store it in a local, gitignored env file or your OS's secret store; never in a tracked file.

**Verify it works:** ask it to list open pull requests on a known repo you have access to.

## Adding another server

Most MCP servers follow the same shape: install the package, add an entry under `mcpServers` in your Claude Code config (project-level `.mcp.json` or user-level config), and verify with one simple read-only call before relying on it. Keep real tokens out of any file this repo tracks; use `mcp.json.example` as the shape and a local, gitignored file for the real values.
