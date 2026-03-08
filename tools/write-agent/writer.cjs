#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const PROJECT_ROOT = path.resolve(process.env.HOME, "projects", "truth-lens");

function safeResolve(relPath) {
  const fullPath = path.resolve(PROJECT_ROOT, relPath);
  if (!fullPath.startsWith(PROJECT_ROOT)) {
    throw new Error(`Blocked path outside project root: ${relPath}`);
  }
  return fullPath;
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function backupFileIfExists(filePath) {
  if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
    const backupPath = `${filePath}.bak`;
    fs.copyFileSync(filePath, backupPath);
    console.log(`[backup] ${backupPath}`);
  }
}

function writeFile(op) {
  const filePath = safeResolve(op.path);
  ensureDir(path.dirname(filePath));

  if (op.backup !== false) {
    backupFileIfExists(filePath);
  }

  fs.writeFileSync(filePath, op.content ?? "", "utf8");
  console.log(`[write] ${op.path}`);
}

function mkdirOp(op) {
  const dirPath = safeResolve(op.path);
  ensureDir(dirPath);
  console.log(`[mkdir] ${op.path}`);
}

function replaceInFile(op) {
  const filePath = safeResolve(op.path);

  if (!fs.existsSync(filePath)) {
    throw new Error(`File not found: ${op.path}`);
  }

  const original = fs.readFileSync(filePath, "utf8");

  if (!original.includes(op.find)) {
    throw new Error(`Find text not found in ${op.path}`);
  }

  const updated = op.all
    ? original.split(op.find).join(op.replace)
    : original.replace(op.find, op.replace);

  if (op.backup !== false) {
    backupFileIfExists(filePath);
  }

  fs.writeFileSync(filePath, updated, "utf8");
  console.log(`[patch] ${op.path}`);
}

function deleteFile(op) {
  const filePath = safeResolve(op.path);
  if (fs.existsSync(filePath)) {
    fs.unlinkSync(filePath);
    console.log(`[delete] ${op.path}`);
  } else {
    console.log(`[skip-delete] ${op.path} not found`);
  }
}

function readInstructionFile(filePath) {
  const raw = fs.readFileSync(filePath, "utf8");
  const parsed = JSON.parse(raw);

  if (!Array.isArray(parsed.operations)) {
    throw new Error(`Instruction file must contain {"operations":[...]}`);
  }

  return parsed;
}

function runOperation(op) {
  if (!op || typeof op !== "object") {
    throw new Error("Invalid operation entry");
  }

  switch (op.action) {
    case "mkdir":
      return mkdirOp(op);
    case "write_file":
      return writeFile(op);
    case "replace_in_file":
      return replaceInFile(op);
    case "delete_file":
      return deleteFile(op);
    default:
      throw new Error(`Unknown action: ${op.action}`);
  }
}

function main() {
  const instructionArg = process.argv[2];

  if (!instructionArg) {
    console.error("Usage: node writer.js <instructions.json>");
    process.exit(1);
  }

  const instructionPath = path.resolve(process.cwd(), instructionArg);
  const instructions = readInstructionFile(instructionPath);

  console.log(`[root] ${PROJECT_ROOT}`);
  console.log(`[ops] ${instructions.operations.length}`);

  for (const op of instructions.operations) {
    runOperation(op);
  }

  console.log("[done]");
}

main();
