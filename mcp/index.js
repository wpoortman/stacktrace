#!/usr/bin/env node
// Stacktrace MCP server — lets an AI assistant log into Stacktrace by writing
// the same data.json the macOS app reads. The app file-watches and reloads, so
// additions appear live.

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { randomUUID } from "node:crypto";
import { homedir } from "node:os";
import fs from "node:fs";
import path from "node:path";

// --- Data file location -----------------------------------------------------
// STACKTRACE_DATA = full path to data.json, or STACKTRACE_DIR = its folder.
// Default = the non-sandboxed Application Support path. For a sandboxed (App
// Store / signed) build, point one of these at the app's storage folder.
function dataPath() {
  if (process.env.STACKTRACE_DATA) return process.env.STACKTRACE_DATA;
  const dir =
    process.env.STACKTRACE_DIR ||
    path.join(homedir(), "Library", "Application Support", "Stacktrace");
  return path.join(dir, "data.json");
}

const EMPTY = {
  entries: [], tags: [], routines: [], routineLogs: [], dayRatings: [], holidays: [],
};

function load() {
  try {
    const raw = fs.readFileSync(dataPath(), "utf8");
    return { ...EMPTY, ...JSON.parse(raw) };
  } catch {
    return { ...EMPTY };
  }
}

function save(store) {
  const file = dataPath();
  fs.mkdirSync(path.dirname(file), { recursive: true });
  if (fs.existsSync(file)) {
    try { fs.copyFileSync(file, file + ".bak"); } catch {}
  }
  const tmp = file + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(store, null, 2));
  fs.renameSync(tmp, file); // atomic
}

// --- Dates: match Swift's local start-of-day, encoded as ISO8601 (no ms) -----
function isoNoMillis(d) {
  return d.toISOString().replace(/\.\d{3}Z$/, "Z");
}
function localDayStartISO(dateStr) {
  let y, m, day;
  if (typeof dateStr === "string" && /^\d{4}-\d{2}-\d{2}$/.test(dateStr)) {
    [y, m, day] = dateStr.split("-").map(Number);
  } else {
    const n = new Date();
    y = n.getFullYear(); m = n.getMonth() + 1; day = n.getDate();
  }
  return isoNoMillis(new Date(y, m - 1, day, 0, 0, 0, 0));
}

// Build an entry with all of ReportEntry's non-optional fields present.
function newEntry(date, extra) {
  return {
    id: randomUUID(),
    date: localDayStartISO(date),
    title: "",
    detail: "",
    wentWell: "",
    wentBad: "",
    tags: [],
    createdAt: isoNoMillis(new Date()),
    ...extra,
  };
}

function dayLabel(iso) {
  return new Date(iso).toLocaleDateString();
}

// --- Tools ------------------------------------------------------------------
const tools = [
  {
    name: "stacktrace_add_entry",
    description:
      "Log a full work entry: what you did, with optional what-went-well / what-went-bad, tags, and a 1-5 mood.",
    inputSchema: {
      type: "object",
      properties: {
        title: { type: "string", description: "Short summary of what you did." },
        detail: { type: "string" },
        wentWell: { type: "string" },
        wentBad: { type: "string" },
        tags: { type: "array", items: { type: "string" } },
        mood: { type: "integer", minimum: 1, maximum: 5 },
        date: { type: "string", description: "YYYY-MM-DD (defaults to today)." },
      },
      required: ["title"],
    },
  },
  {
    name: "stacktrace_add_win",
    description: "Log a quick win (one line).",
    inputSchema: {
      type: "object",
      properties: { text: { type: "string" }, date: { type: "string" } },
      required: ["text"],
    },
  },
  {
    name: "stacktrace_add_setback",
    description: "Log a quick setback (one line).",
    inputSchema: {
      type: "object",
      properties: { text: { type: "string" }, date: { type: "string" } },
      required: ["text"],
    },
  },
  {
    name: "stacktrace_add_exercise",
    description: "Log an exercise activity with a duration in minutes.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string" },
        minutes: { type: "integer", minimum: 1 },
        date: { type: "string" },
      },
      required: ["name", "minutes"],
    },
  },
  {
    name: "stacktrace_set_day_score",
    description: "Set the overall 1-10 score for a day.",
    inputSchema: {
      type: "object",
      properties: {
        score: { type: "integer", minimum: 1, maximum: 10 },
        date: { type: "string" },
      },
      required: ["score"],
    },
  },
  {
    name: "stacktrace_today",
    description: "Summarize what's logged for a day (defaults to today).",
    inputSchema: {
      type: "object",
      properties: { date: { type: "string" } },
    },
  },
];

function clampInt(v, lo, hi) {
  return Math.max(lo, Math.min(hi, Math.round(v)));
}

function handle(name, args) {
  args = args || {};
  const store = load();

  switch (name) {
    case "stacktrace_add_entry": {
      const e = newEntry(args.date, {
        title: String(args.title),
        detail: args.detail || "",
        wentWell: args.wentWell || "",
        wentBad: args.wentBad || "",
        tags: Array.isArray(args.tags) ? args.tags : [],
      });
      if (args.mood != null) e.mood = clampInt(args.mood, 1, 5);
      store.entries.push(e);
      for (const t of e.tags) if (!store.tags.includes(t)) store.tags.push(t);
      save(store);
      return `Logged entry "${e.title}".`;
    }
    case "stacktrace_add_win": {
      const e = newEntry(args.date, { quickKind: "win", detail: String(args.text), mood: 5 });
      store.entries.push(e);
      save(store);
      return `Logged win: ${e.detail}`;
    }
    case "stacktrace_add_setback": {
      const e = newEntry(args.date, { quickKind: "fail", detail: String(args.text), mood: 2 });
      store.entries.push(e);
      save(store);
      return `Logged setback: ${e.detail}`;
    }
    case "stacktrace_add_exercise": {
      const e = newEntry(args.date, {
        exercise: String(args.name),
        durationMinutes: clampInt(args.minutes, 1, 100000),
      });
      store.entries.push(e);
      save(store);
      return `Logged exercise: ${e.exercise} — ${e.durationMinutes} min.`;
    }
    case "stacktrace_set_day_score": {
      const day = localDayStartISO(args.date);
      store.dayRatings = store.dayRatings.filter((r) => r.day !== day);
      store.dayRatings.push({
        id: randomUUID(),
        day,
        score: clampInt(args.score, 1, 10),
        at: isoNoMillis(new Date()),
      });
      save(store);
      return `Set day score to ${clampInt(args.score, 1, 10)}/10 for ${dayLabel(day)}.`;
    }
    case "stacktrace_today": {
      const day = localDayStartISO(args.date);
      const todays = store.entries.filter((e) => e.date === day);
      if (!todays.length) return `Nothing logged for ${dayLabel(day)}.`;
      const lines = todays.map((e) => {
        if (e.quickKind === "win") return `- win: ${e.detail}`;
        if (e.quickKind === "fail") return `- setback: ${e.detail}`;
        if (e.exercise) return `- exercise: ${e.exercise} (${e.durationMinutes} min)`;
        return `- ${e.title || "Untitled"}${e.mood ? ` (mood ${e.mood}/5)` : ""}`;
      });
      const rating = store.dayRatings.find((r) => r.day === day);
      if (rating) lines.push(`- day score: ${rating.score}/10`);
      return `${dayLabel(day)}:\n${lines.join("\n")}`;
    }
    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

// --- Wire up ----------------------------------------------------------------
const server = new Server(
  { name: "stacktrace", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools }));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  try {
    const text = handle(req.params.name, req.params.arguments);
    return { content: [{ type: "text", text }] };
  } catch (err) {
    return { content: [{ type: "text", text: `Error: ${err.message}` }], isError: true };
  }
});

await server.connect(new StdioServerTransport());
