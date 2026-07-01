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

  return entries.slice(0, limit).map((entry) => {
    const match = entry.match(/^- \*\*([\s\S]*?)\*\*([\s\S]*)$/);
    const title = stripMarkdown(match?.[1] ?? "").replace(/:$/, "");
    const body = excerpt(match?.[2] ?? "", 210);
    const dateMatch = title.match(/^(\d{4}-\d{2}-\d{2})\s+—\s+(.+)$/);
    return {
      date: dateMatch?.[1] ?? "",
      title: dateMatch?.[2] ?? title,
      body,
    };
  });
}

function parsePhases(markdown) {
  const matches = [...markdown.matchAll(/^### (Phase [^\n]+)$/gm)];
  return matches.map((match) => {
    const title = stripMarkdown(match[1]);
    const start = match.index + match[0].length;
    const nextIndex = markdown.slice(start).search(/\n### Phase /);
    const section = nextIndex === -1 ? markdown.slice(start) : markdown.slice(start, start + nextIndex);
    const counts = checkboxCounts(section);
    const isDone = title.includes("✅ DONE") || (counts.total > 0 && counts.pending === 0 && counts.partial === 0);
    const isInProgress = title.includes("IN PROGRESS") || counts.partial > 0;
    const cleanTitle = title.replace(/\s+✅ DONE/g, "").replace(/\s+— IN PROGRESS/g, "").trim();

    return {
      title: cleanTitle,
      status: isDone ? "done" : isInProgress ? "in progress" : "planned",
      counts,
      summary: excerpt(section, 180),
    };
  });
}

function parseBacklog(markdown, limit = 6) {
  const entries = markdown
    .split(/\n(?=### [A-Z]+-\d+ — )/g)
    .filter((entry) => entry.trim().startsWith("### "));

  return entries.slice(0, limit).map((entry) => {
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
  });
}

function buildRoadmapCards(phases, progressLog) {
  const doneCount = phases.filter((phase) => phase.status === "done").length;
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

const [roadmapMarkdown, backlogMarkdown] = await Promise.all([
  readFile(path.join(repoRoot, "docs/ROADMAP.md"), "utf8"),
  readFile(path.join(repoRoot, "docs/BACKLOG.md"), "utf8"),
]);

const phases = parsePhases(roadmapMarkdown);
const progressLog = parseProgressLog(roadmapMarkdown);
const backlog = parseBacklog(backlogMarkdown);

const content = {
  generatedAt: new Date().toISOString(),
  sourceFiles: ["docs/ROADMAP.md", "docs/BACKLOG.md"],
  roadmap: buildRoadmapCards(phases, progressLog),
  progressLog,
  backlog,
  counts: {
    phases: {
      done: phases.filter((phase) => phase.status === "done").length,
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

console.log(`synced ${content.roadmap.length} roadmap cards, ${content.progressLog.length} progress notes, ${content.backlog.length} backlog items`);
