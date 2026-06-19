# Stacktrace MCP server

Lets an AI assistant (Claude Desktop, Claude Code, or any MCP client) log into
Stacktrace. You just say *"register this in Stacktrace"* and the assistant calls
a tool that writes to the same `data.json` the app reads. The app watches the
file and updates live.

## Tools

- `stacktrace_add_entry` — full entry (title, detail, what went well/bad, tags, 1–5 mood)
- `stacktrace_add_win` / `stacktrace_add_setback` — one-line quick items
- `stacktrace_add_exercise` — name + minutes
- `stacktrace_set_day_score` — overall 1–10 for a day
- `stacktrace_today` — read back what's logged for a day

All take an optional `date` (`YYYY-MM-DD`, defaults to today).

## Install

```bash
cd mcp
npm install
```

## Configure your MCP client

**Claude Code:**

```bash
claude mcp add stacktrace -- node /absolute/path/to/stacktrace/mcp/index.js
```

**Claude Desktop** — add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "stacktrace": {
      "command": "node",
      "args": ["/absolute/path/to/stacktrace/mcp/index.js"]
    }
  }
}
```

Then: *"Add a win to Stacktrace: shipped the export feature."*

## Where it writes

Defaults to `~/Library/Application Support/Stacktrace/data.json`.

**Important — sandboxed builds:** a signed/App Store build is sandboxed, so the
app's data actually lives in its container, not the path above. Point the
server at the right folder with an env var, **or** (simplest) set a custom
storage folder in the app (Settings → Storage → Change…) that both the app and
this server can reach, e.g. `~/Documents/Stacktrace`:

```json
{
  "mcpServers": {
    "stacktrace": {
      "command": "node",
      "args": ["/absolute/path/to/stacktrace/mcp/index.js"],
      "env": { "STACKTRACE_DIR": "/Users/you/Documents/Stacktrace" }
    }
  }
}
```

`STACKTRACE_DATA` (full path to `data.json`) overrides `STACKTRACE_DIR`.

## Notes

- Writes are atomic (temp + rename) and keep a `.bak`, matching the app.
- Only the documented fields are written; the JSON schema matches the app's
  `data.json` exactly.
