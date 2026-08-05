import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "../..");
const outputPath = path.resolve(scriptDir, "../src/generated/siteContent.json");

function normalizeWhitespace(value) {
  return value
    .replace(/\s+/g, " ")
    .replace(/\s+([,.;:])/g, "$1")
    .trim();
}

function stripMarkdown(value) {
  return normalizeWhitespace(
    value
      .replace(/`([^`]+)`/g, "$1")
      .replace(/\*\*([^*]+)\*\*/g, "$1")
      .replace(/\*([^*]+)\*/g, "$1")
      .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
      .replace(/^#+\s+/gm, "")
      .replace(/^[-*]\s+/gm, ""),
  );
}

function excerpt(value, maxLength = 190) {
  const clean = stripMarkdown(value);
  if (clean.length <= maxLength) {
    return clean;
  }
  return `${clean.slice(0, maxLength).replace(/\s+\S*$/, "")}...`;
}

function getSection(markdown, heading) {
  const start = markdown.indexOf(heading);
  if (start === -1) {
    return "";
  }
  const rest = markdown.slice(start + heading.length);
  const next = rest.search(/\n##\s+/);
  return next === -1 ? rest : rest.slice(0, next);
}

function checkboxCounts(markdown) {
  const done = (markdown.match(/- \[x\]/gi) ?? []).length;
  const pending = (markdown.match(/- \[ \]/g) ?? []).length;
  const partial = (markdown.match(/- \[~\]/g) ?? []).length;
  return {
    done,
    pending,
    partial,
    total: done + pending + partial,
  };
}

function parseProgressLog(markdown, limit = 5) {
  const progress = getSection(markdown, "## Progress Log");
  const entries = progress
    .split(/\n(?=- \*\*)/g)
    .filter((entry) => entry.trim().startsWith("- **"));

  return entries.map((entry) => {
    const match = entry.match(/^- \*\*([\s\S]*?)\*\*([\s\S]*)$/);
    const title = stripMarkdown(match?.[1] ?? "").replace(/:$/, "");
    const body = excerpt(match?.[2] ?? "", 210);
    const dateMatch = title.match(/^(\d{4}-\d{2}-\d{2})\s+—\s+(.+)$/);
    return {
      date: dateMatch?.[1] ?? "",
      title: dateMatch?.[2] ?? title,
      body,
      hidden: /\[(site|website|internal)\]/i.test(`${title} ${match?.[2] ?? ""}`),
    };
  })
    .filter((entry) => !entry.hidden)
    .slice(0, limit)
    .map(({ hidden, ...entry }) => entry);
}

function parsePhases(markdown) {
  const matches = [...markdown.matchAll(/^### (Phase [^\n]+)$/gm)];
  return matches.map((match) => {
    const title = stripMarkdown(match[1]);
    const start = match.index + match[0].length;
    const nextIndex = markdown.slice(start).search(/\n### Phase /);
    const section = nextIndex === -1 ? markdown.slice(start) : markdown.slice(start, start + nextIndex);
    const counts = checkboxCounts(section);
    // Three shipped-state tiers:
    //   "done"                        — phase complete
    //   "done · refinements planned"  — shipped and usable today; follow-up
    //                                    improvements are queued (header marker
    //                                    "✅ DONE — refinements planned")
    //   "in progress" / "planned"     — as before
    const isRefining = title.includes("✅ DONE — refinements planned");
    const isDone =
      !isRefining &&
      (title.includes("✅ DONE") || (counts.total > 0 && counts.pending === 0 && counts.partial === 0));
    const isInProgress = title.includes("IN PROGRESS") || counts.partial > 0 || counts.done > 0;
    const cleanTitle = title
      .replace(/\s+✅ DONE — refinements planned/g, "")
      .replace(/\s+✅ DONE/g, "")
      .replace(/\s+— IN PROGRESS/g, "")
      .replace(/\s*\(Session \d+[a-z]?\)/g, "")
      .trim();

    return {
      title: cleanTitle,
      status: isRefining
        ? "done · refinements planned"
        : isDone
          ? "done"
          : isInProgress
            ? "in progress"
            : "planned",
      counts,
      summary: excerpt(section, 180),
    };
  });
}

function parseBacklog(markdown, limit = 6) {
  const entries = markdown
    .split(/\n(?=### [A-Z]+-\d+ — )/g)
    .filter((entry) => entry.trim().startsWith("### "));

  return entries.map((entry) => {
    const match = entry.match(/^### ([A-Z]+-\d+) — ([^\n]+)\n([\s\S]*)$/);
    const body = match?.[3] ?? "";
    const field = (name) => {
      const lines = body.split("\n");
      const start = lines.findIndex((line) => line.startsWith(`- ${name}:`));
      if (start === -1) {
        return "";
      }

      const collected = [lines[start].replace(`- ${name}:`, "").trim()];
      for (const line of lines.slice(start + 1)) {
        if (line.startsWith("- ")) {
          break;
        }
        collected.push(line.trim());
      }
      return stripMarkdown(collected.join(" "));
    };
    return {
      id: match?.[1] ?? "",
      title: stripMarkdown(match?.[2] ?? ""),
      type: field("Type"),
      priority: field("Priority"),
      area: field("Area"),
      status: field("Status"),
      detail: excerpt(field("Repro/Detail"), 180),
    };
  })
    .filter((item) => !/^done/i.test(item.status))
    .slice(0, limit);
}

function buildRoadmapCards(phases, progressLog) {
  const doneCount = phases.filter((phase) => phase.status.startsWith("done")).length;
  const latest = progressLog[0];

  return [
    {
      status: "shipped",
      title: `${doneCount} phases shipped`,
      body: "the roadmap is the source of truth, with completed phases counted directly from checked project memory.",
    },
    {
      status: "latest",
      title: latest?.title ?? "latest build note",
      body: latest?.body ?? "new progress entries will appear here after ROADMAP.md is updated.",
    },
    {
      status: "next",
      title: "current queue",
      body: "open bugs, feature ideas, and performance work are pulled from BACKLOG.md during the site build.",
    },
    {
      status: "queue",
      title: "backlog queue",
      body: "bugs, feature ideas, and performance work are pulled from BACKLOG.md so tester-facing priorities stay visible.",
    },
  ];
}

const testerPhaseCopy = [
  {
    match: "Phase 1",
    title: "Canvas basics",
    body: "Pan, zoom, create artboards, move boards around, and select work on a native Mac canvas.",
  },
  {
    match: "Phase 2",
    title: "Files that open quickly",
    body: "EXP documents save as a lightweight .design format, with undo-aware document changes.",
  },
  {
    match: "Phase 3",
    title: "Shapes, text, and layers",
    body: "Draw rectangles, ellipses, straight lines, paths, and text; move, resize, rename, lock, hide, group, and reorder layers.",
  },
  {
    match: "Phase 4",
    title: "Source components",
    body: "Create reusable source components, place instances, edit the source, detach when needed, and test text/color/visibility overrides.",
  },
  {
    match: "Phase 5 — Export",
    title: "Export",
    body: "Export selected or all artboards as PNG, PDF, SVG, or a combined multi-page PDF.",
  },
  {
    match: "Phase 5.5",
    title: "Artboard workflows",
    body: "Use presets, resize and rename boards, multi-select, duplicate, copy/paste, and rearrange boards with their contents.",
  },
  {
    match: "Phase 6",
    title: "Handoff notes",
    body: "Attach notes to artboards, keep those notes with duplicated boards, and include notes pages in PDF handoff exports.",
  },
  {
    match: "Phase 8",
    title: "Color and gradients",
    body: "Use the custom color picker, eyedropper, HEX/RGB/HSL/LCH/OKLCH readouts, artboard backgrounds, gradients, and gradient overrides.",
  },
  {
    match: "Phase 9",
    title: "Typography",
    body: "Pick typefaces, style rich text, tune alignment/line height/tracking, transform case, and convert text into editable outlines.",
  },
  {
    match: "Phase 10",
    title: "Effects",
    body: "Adjust opacity with number-key shortcuts, add drop and inner shadows, and layer stackable noise and dissolve texture effects that round-trip through SVG.",
  },
  {
    match: "Phase 11",
    title: "Layout help",
    body: "Try align/distribute, option-hover measurements, rulers, guides, global grids, artboard layout grids, and snapping.",
  },
  {
    match: "Phase 13",
    title: "Workspace and panels",
    body: "Switch between single-window and multi-window panel layouts, move trays, collapse panels, and preserve workspace preferences.",
  },
];

const testerLatestReleaseCopy = [
  {
    phase: "v2.2 — Rendered HTML + CSS import",
    title: "Rendered pages become editable",
    status: "done",
    body: "Import a local or Chrome-saved HTML/CSS package at selected viewports, edit the reconstructed layers, and review an honest report when browser features cannot map exactly.",
  },
  {
    phase: "v2.2 — Static Storybook + CodePen",
    title: "Component builds in, CodePen both ways",
    status: "done",
    body: "Search and import stories from a published static Storybook build without running its toolchain, send an artboard to CodePen, or bring a CodePen export back into EXP.",
  },
  {
    phase: "v2.1 — Nested components + semantic containment",
    title: "Nested, stateful components",
    status: "done",
    body: "Nest component sources safely, set states at every level, expose selected properties, fork a source into a new component, and keep instance overrides and semantic relationships stable.",
  },
  {
    phase: "v2.1 — Canvas pages",
    title: "Browser-style canvas pages",
    status: "done",
    body: "Split large documents across clear page tabs with independent cameras, guides, Layers, and selection; move or duplicate layers and artboards between pages without losing structure.",
  },
  {
    phase: "v2.1 — Shared importer pipeline",
    title: "Editable XD and Figma import",
    status: "done",
    body: "Rescue local Adobe XD documents or import Figma files through the sanctioned REST API, map source pages to EXP tabs, and review honest fidelity notes only when something needs attention.",
  },
  {
    phase: "v2.1 — Handoff + panel IA",
    title: "One Handoff home",
    status: "done",
    body: "Export artboards, semantic HTML, design tokens, or a complete Handoff Package from one panel—and optionally let your own local agent inspect the document through six read-only tools.",
  },
];

function buildTesterFeatures(phases) {
  const phaseFeatures = testerPhaseCopy
    .map((copy) => {
      const phase = phases.find((item) => item.title.includes(copy.match));
      if (!phase) {
        return null;
      }

      return {
        phase: phase.title,
        title: copy.title,
        status: phase.status,
        body: copy.body,
      };
    })
    .filter(Boolean);

  return [...phaseFeatures, ...testerLatestReleaseCopy];
}

function buildTesterKnownIssues(backlog, limit = 4) {
  return backlog
    .filter((item) => item.type === "bug" && !/^done/i.test(item.status))
    .slice(0, limit)
    .map((item) => ({
      id: item.id,
      title: item.title,
      priority: item.priority,
      status: item.status,
      detail: item.detail,
    }));
}

const [roadmapMarkdown, backlogMarkdown] = await Promise.all([
  readFile(path.join(repoRoot, "docs/ROADMAP.md"), "utf8"),
  readFile(path.join(repoRoot, "docs/BACKLOG.md"), "utf8"),
]);

function parseRelease(markdown) {
  const matches = [...markdown.matchAll(/^##\s+v(\d+(?:\.\d+)*)\s+—\s+shipped\s+\((\d{4}-\d{2}-\d{2})\)/gm)];
  if (matches.length === 0) return null;
  // Newest shipped heading wins (by date).
  const latest = matches
    .map((m) => ({ version: m[1], date: m[2] }))
    .sort((a, b) => (a.date < b.date ? 1 : a.date > b.date ? -1 : 0))[0];
  return latest;
}

function appcastDateToISO(pubDate) {
  if (!pubDate) return "";
  const parsed = new Date(pubDate);
  return Number.isNaN(parsed.valueOf()) ? "" : parsed.toISOString().slice(0, 10);
}

function parseReleaseFromAppcast(appcast) {
  const items = [...appcast.matchAll(/<item>([\s\S]*?)<\/item>/g)]
    .map((match) => {
      const item = match[1];
      const version = item.match(/<sparkle:shortVersionString>([^<]+)<\/sparkle:shortVersionString>/)?.[1]?.trim();
      const build = Number(item.match(/<sparkle:version>([^<]+)<\/sparkle:version>/)?.[1] ?? 0);
      const pubDate = item.match(/<pubDate>([^<]+)<\/pubDate>/)?.[1]?.trim() ?? "";
      return version ? { version, build, date: appcastDateToISO(pubDate), source: "appcast" } : null;
    })
    .filter(Boolean)
    .sort((a, b) => b.build - a.build);

  return items[0] ?? null;
}

async function loadAppcastRelease() {
  try {
    const appcast = await readFile(path.join(repoRoot, "website/public/appcast.xml"), "utf8");
    return parseReleaseFromAppcast(appcast);
  } catch {
    return null;
  }
}

async function loadLearnVideos() {
  try {
    const raw = await readFile(path.join(repoRoot, "docs/learn-videos.json"), "utf8");
    const parsed = JSON.parse(raw);
    const videos = Array.isArray(parsed.videos) ? parsed.videos : [];
    return videos
      .filter((v) => v && v.title)
      .slice()
      .sort((a, b) => (a.order ?? 999) - (b.order ?? 999));
  } catch {
    return [];
  }
}

const phases = parsePhases(roadmapMarkdown);
const progressLog = parseProgressLog(roadmapMarkdown);
const backlog = parseBacklog(backlogMarkdown);
const release = (await loadAppcastRelease()) ?? parseRelease(roadmapMarkdown);
const learnVideos = await loadLearnVideos();

const content = {
  generatedAt: new Date().toISOString(),
  sourceFiles: ["docs/ROADMAP.md", "docs/BACKLOG.md", "website/public/appcast.xml"],
  release,
  learnVideos,
  roadmap: buildRoadmapCards(phases, progressLog),
  testerFeatures: buildTesterFeatures(phases),
  testerKnownIssues: buildTesterKnownIssues(backlog),
  progressLog,
  backlog,
  counts: {
    phases: {
      done: phases.filter((phase) => phase.status === "done").length,
      doneRefining: phases.filter((phase) => phase.status === "done · refinements planned").length,
      inProgress: phases.filter((phase) => phase.status === "in progress").length,
      planned: phases.filter((phase) => phase.status === "planned").length,
      total: phases.length,
    },
    backlog: {
      open: backlog.filter((item) => item.status === "open").length,
      inProgress: backlog.filter((item) => item.status === "in-progress").length,
      needsVerify: backlog.filter((item) => item.status === "needs-verify").length,
    },
  },
};

await mkdir(path.dirname(outputPath), { recursive: true });
await writeFile(outputPath, `${JSON.stringify(content, null, 2)}\n`);

console.log(`synced ${content.roadmap.length} roadmap cards, ${content.progressLog.length} progress notes, ${content.backlog.length} backlog items, release ${release?.version ?? "?"}, ${learnVideos.length} learn videos`);
