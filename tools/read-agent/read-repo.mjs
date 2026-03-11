#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const ROOT = path.resolve(process.env.HOME || ".", "projects", "truth-lens");
const args = process.argv.slice(2);

function exists(p) {
  try {
    fs.accessSync(p);
    return true;
  } catch {
    return false;
  }
}

function readText(p) {
  return fs.readFileSync(p, "utf8");
}

function rel(p) {
  return path.relative(ROOT, p) || ".";
}

function walk(dir, out = []) {
  const skip = new Set(["node_modules", ".git", "dist"]);
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (skip.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(full + "/");
      walk(full, out);
    } else {
      out.push(full);
    }
  }
  return out;
}

function grepInFile(file, pattern) {
  const text = readText(file);
  const lines = text.split("\n");
  const hits = [];
  const rx = new RegExp(pattern);
  for (let i = 0; i < lines.length; i++) {
    if (rx.test(lines[i])) {
      hits.push({ line: i + 1, text: lines[i] });
    }
  }
  return hits;
}

function safeList(files, max = 200) {
  return files.slice(0, max).map(rel);
}

function section(title, body) {
  return `\n=== ${title} ===\n${body}\n`;
}

function fileSnippet(file, start = 1, count = 80) {
  const text = readText(file).split("\n");
  const end = Math.min(text.length, start - 1 + count);
  return text
    .slice(start - 1, end)
    .map((line, idx) => `${start + idx}: ${line}`)
    .join("\n");
}

function repoSummaryText() {
  const files = walk(ROOT);
  const dirs = files.filter((p) => p.endsWith("/"));
  const regular = files.filter((p) => !p.endsWith("/"));

  let out = "";
  out += section("ROOT", ROOT);
  out += section("DIR COUNT", String(dirs.length));
  out += section("FILE COUNT", String(regular.length));
  out += section("TREE SAMPLE", safeList(files, 150).join("\n"));

  const keyFiles = [
    "package.json",
    "apps/api/src/server.ts",
    "apps/worker/src/worker.ts",
    "packages/storage/src/storage.js",
    "packages/dashboard/src/index.js",
    "packages/reddit/src/fetch.ts"
  ];

  for (const k of keyFiles) {
    const full = path.join(ROOT, k);
    if (exists(full)) {
      out += section(`FILE ${k}`, fileSnippet(full, 1, 80));
    }
  }

  return out;
}

function grepRepoText(pattern) {
  const files = walk(ROOT).filter((p) => !p.endsWith("/"));
  let out = "";
  let total = 0;

  for (const file of files) {
    try {
      const hits = grepInFile(file, pattern);
      if (hits.length) {
        out += `\n--- ${rel(file)} ---\n`;
        for (const hit of hits.slice(0, 20)) {
          out += `${hit.line}: ${hit.text}\n`;
          total += 1;
        }
      }
    } catch {}
  }

  if (!total) out = "No matches.\n";
  return out;
}

function bugScanText() {
  const targets = [
    "packages/storage/src/storage.js",
    "apps/api/src/server.ts",
    "apps/worker/src/worker.ts",
    "packages/dashboard/src/index.js"
  ];

  let out = "";
  out += section("BUG SCAN TARGETS", targets.join("\n"));

  for (const t of targets) {
    const full = path.join(ROOT, t);
    if (!exists(full)) continue;
    const text = readText(full);

    const findings = [];
    if (text.includes("module.exports")) findings.push("contains module.exports");
    if (text.includes("export function")) findings.push("contains export function");
    if (text.includes("require(")) findings.push("contains require()");
    if (text.includes("import ")) findings.push("contains import");
    if (text.includes("/dashboard")) findings.push("contains dashboard routes/links");
    if (text.includes("/activity")) findings.push("contains activity routes/links");

    out += section(`SCAN ${t}`, findings.length ? findings.join("\n") : "no obvious mixed-module flags");
    out += fileSnippet(full, 1, 120) + "\n";
  }

  return out;
}

function routeScanText() {
  const server = path.join(ROOT, "apps/api/src/server.ts");
  if (!exists(server)) return "server.ts not found\n";
  const hits = grepInFile(server, "url\\.pathname|parts\\[0\\]|routes:");
  return hits.map((h) => `${h.line}: ${h.text}`).join("\n") + "\n";
}

function showFileText(target) {
  const full = path.isAbsolute(target) ? target : path.join(ROOT, target);
  if (!exists(full)) {
    return `File not found: ${full}\n`;
  }
  return fileSnippet(full, 1, 240) + "\n";
}

function parseImports(file) {
  const text = readText(file);
  const lines = text.split("\n");
  const out = [];
  const rx = /from\s+['"](.+?)['"]/;

  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(rx);
    if (m) {
      out.push({
        line: i + 1,
        from: m[1]
      });
    }
  }
  return out;
}

function resolveImport(sourceFile, spec) {
  if (!spec.startsWith(".")) return { type: "package", resolved: spec, exists: true };
  const base = path.dirname(sourceFile);
  const full = path.resolve(base, spec);
  return {
    type: "relative",
    resolved: full,
    exists: exists(full)
  };
}

function doctorData() {
  const findings = [];
  const warnings = [];
  const notes = [];
  const suggestions = new Set();

  const packageJson = path.join(ROOT, "package.json");
  let packageType = "unknown";
  if (exists(packageJson)) {
    try {
      const pkg = JSON.parse(readText(packageJson));
      packageType = pkg.type || "commonjs-default";
      notes.push(`package.json type = ${packageType}`);
    } catch {
      warnings.push("Could not parse package.json");
    }
  } else {
    warnings.push("package.json missing");
  }

  const criticalFiles = [
    "apps/api/src/server.ts",
    "apps/worker/src/worker.ts",
    "packages/storage/src/storage.js",
    "packages/dashboard/src/index.js",
    "packages/reddit/src/fetch.ts",
    "packages/narratives/src/index.js",
    "packages/cluster/src/index.js",
    "packages/baseline/src/index.js",
    "packages/spread/src/index.js",
    "packages/findings/src/index.js"
  ];

  let missingPackageFile = false;

  for (const f of criticalFiles) {
    const full = path.join(ROOT, f);
    if (!exists(full)) {
      findings.push(`Missing critical file: ${f}`);
      if (f.startsWith("packages/")) missingPackageFile = true;
      if (f.startsWith("apps/api/")) suggestions.add("tl-fix-api");
      if (f.startsWith("packages/dashboard/")) suggestions.add("tl-fix-dashboard");
    }
  }

  if (missingPackageFile) suggestions.add("tl-fix-packages");

  const syntaxTargets = criticalFiles
    .map((f) => path.join(ROOT, f))
    .filter(exists);

  let storageIssue = false;
  let dashboardIssue = false;
  let apiIssue = false;

  for (const full of syntaxTargets) {
    const text = readText(full);
    const hasImport = /\bimport\b/.test(text);
    const hasExport = /\bexport\b/.test(text);
    const hasRequire = /\brequire\s*\(/.test(text);
    const hasModuleExports = /\bmodule\.exports\b/.test(text);

    if ((hasImport || hasExport) && (hasRequire || hasModuleExports)) {
      findings.push(`Mixed module syntax in ${rel(full)}`);
      if (rel(full).includes("storage.js")) storageIssue = true;
      if (rel(full).includes("dashboard/src/index.js")) dashboardIssue = true;
      if (rel(full).includes("apps/api/src/server.ts")) apiIssue = true;
    }

    if (packageType === "module" && (hasRequire || hasModuleExports)) {
      findings.push(`CommonJS syntax inside ESM project file ${rel(full)}`);
      if (rel(full).includes("storage.js")) storageIssue = true;
      if (rel(full).includes("dashboard/src/index.js")) dashboardIssue = true;
      if (rel(full).includes("apps/api/src/server.ts")) apiIssue = true;
    }

    if (packageType !== "module" && (hasImport || hasExport) && full.endsWith(".js")) {
      warnings.push(`ESM syntax in .js file while package type is ${packageType}: ${rel(full)}`);
    }
  }

  const importTargets = [
    path.join(ROOT, "apps/api/src/server.ts"),
    path.join(ROOT, "apps/worker/src/worker.ts")
  ].filter(exists);

  for (const file of importTargets) {
    for (const imp of parseImports(file)) {
      const r = resolveImport(file, imp.from);
      if (r.type === "relative" && !r.exists) {
        findings.push(`Broken import in ${rel(file)}:${imp.line} -> ${imp.from}`);
        apiIssue = apiIssue || rel(file).includes("server.ts");
        if (imp.from.includes("dashboard")) dashboardIssue = true;
        if (imp.from.includes("storage")) storageIssue = true;
        if (imp.from.includes("narratives") || imp.from.includes("cluster") || imp.from.includes("baseline") || imp.from.includes("spread") || imp.from.includes("findings")) {
          suggestions.add("tl-fix-packages");
        }
      }
    }
  }

  const server = path.join(ROOT, "apps/api/src/server.ts");
  if (exists(server)) {
    const s = readText(server);

    const hasDashboardRoute = s.includes("'/dashboard'") || s.includes('"/dashboard"') || s.includes("url.pathname === '/dashboard'");
    const hasActivityRoute = s.includes("/activity");
    const hasFindingsRoute = s.includes("/findings");
    const hasBaselinesRoute = s.includes("/baselines");
    const hasNarrativesRoute = s.includes("/narratives");
    const hasClustersRoute = s.includes("/clusters");

    if (!hasDashboardRoute) {
      findings.push("Dashboard route missing from server.ts");
      apiIssue = true;
    }
    if (!hasActivityRoute) {
      warnings.push("Activity route missing from server.ts");
      apiIssue = true;
    }
    if (!hasFindingsRoute) warnings.push("Findings route missing from server.ts");
    if (!hasBaselinesRoute) warnings.push("Baselines route missing from server.ts");
    if (!hasNarrativesRoute) warnings.push("Narratives route missing from server.ts");
    if (!hasClustersRoute) warnings.push("Clusters route missing from server.ts");
  }

  const dash = path.join(ROOT, "packages/dashboard/src/index.js");
  if (exists(dash)) {
    const d = readText(dash);
    if (!d.includes("/dashboard/cluster/")) {
      warnings.push("Dashboard cluster detail links may be missing");
      dashboardIssue = true;
    }
    if (!d.includes("/dashboard/narrative/")) {
      warnings.push("Dashboard narrative detail links may be missing");
      dashboardIssue = true;
    }
    if (!d.includes("renderDashboard")) {
      findings.push("renderDashboard export missing");
      dashboardIssue = true;
    }
  }

  if (storageIssue) suggestions.add("tl-fix-storage");
  if (dashboardIssue) suggestions.add("tl-fix-dashboard");
  if (apiIssue) suggestions.add("tl-fix-api");

  if (findings.length >= 3) suggestions.add("tl-fix-all");
  if (!suggestions.size && !findings.length) notes.push("No obvious repair command suggested.");

  return {
    notes,
    findings,
    warnings,
    suggestions: [...suggestions]
  };
}

function doctorText() {
  const data = doctorData();
  let out = "";
  out += section("DOCTOR NOTES", data.notes.length ? data.notes.join("\n") : "none");
  out += section("DOCTOR FINDINGS", data.findings.length ? data.findings.join("\n") : "No critical findings.");
  out += section("DOCTOR WARNINGS", data.warnings.length ? data.warnings.join("\n") : "No warnings.");
  out += section(
    "SUGGESTED FIX COMMANDS",
    data.suggestions.length ? data.suggestions.join("\n") : "No fix command suggested."
  );
  return out;
}

function print(text) {
  process.stdout.write(text);
}

function writeReport() {
  const reportFile = path.join(ROOT, "debug-report.txt");
  let out = "";
  out += section("DEBUG REPORT GENERATED", new Date().toISOString());
  out += doctorText();
  out += repoSummaryText();
  out += section("BUG SCAN", bugScanText());
  out += section("ROUTE SCAN", routeScanText());
  out += section("GREP dashboard", grepRepoText("dashboard"));
  out += section("GREP module.exports", grepRepoText("module\\.exports"));
  out += section("GREP export function", grepRepoText("export function"));
  out += section("FILE apps/api/src/server.ts", showFileText("apps/api/src/server.ts"));
  out += section("FILE packages/storage/src/storage.js", showFileText("packages/storage/src/storage.js"));
  out += section("FILE packages/dashboard/src/index.js", showFileText("packages/dashboard/src/index.js"));

  fs.writeFileSync(reportFile, out, "utf8");
  print(`Wrote ${reportFile}\n`);
}

function help() {
  print(`
Usage:
  node tools/read-agent/read-repo.mjs summary
  node tools/read-agent/read-repo.mjs bugscan
  node tools/read-agent/read-repo.mjs routes
  node tools/read-agent/read-repo.mjs grep "dashboard"
  node tools/read-agent/read-repo.mjs file apps/api/src/server.ts
  node tools/read-agent/read-repo.mjs report
  node tools/read-agent/read-repo.mjs doctor
`);
}

const cmd = args[0];

switch (cmd) {
  case "summary":
    print(repoSummaryText());
    break;
  case "bugscan":
    print(bugScanText());
    break;
  case "routes":
    print(routeScanText());
    break;
  case "grep":
    print(grepRepoText(args[1] || ""));
    break;
  case "file":
    print(showFileText(args[1] || ""));
    break;
  case "report":
    writeReport();
    break;
  case "doctor":
    print(doctorText());
    break;
  default:
    help();
}
