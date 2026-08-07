#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const START = "<!-- agent-config:hermes-orca-coordinator:start -->";
const END = "<!-- agent-config:hermes-orca-coordinator:end -->";

function valueAfter(flag) {
  const index = process.argv.indexOf(flag);
  if (index === -1 || !process.argv[index + 1]) {
    throw new Error(`Missing ${flag}`);
  }
  return process.argv[index + 1];
}

function findBlocks(content) {
  const blocks = [];
  let cursor = 0;

  while (cursor < content.length) {
    const start = content.indexOf(START, cursor);
    const strayEnd = content.indexOf(END, cursor);
    if (start === -1) {
      if (strayEnd !== -1) throw new Error("Coordinator SOUL block has an unmatched end marker");
      break;
    }
    if (strayEnd !== -1 && strayEnd < start) {
      throw new Error("Coordinator SOUL block has an unmatched end marker");
    }

    const endMarker = content.indexOf(END, start + START.length);
    if (endMarker === -1) throw new Error("Coordinator SOUL block has an unmatched start marker");
    const nestedStart = content.indexOf(START, start + START.length);
    if (nestedStart !== -1 && nestedStart < endMarker) {
      throw new Error("Coordinator SOUL block has nested start markers");
    }

    let end = endMarker + END.length;
    if (content.slice(end, end + 2) === "\r\n") end += 2;
    else if (content[end] === "\n") end += 1;
    blocks.push({ start, end });
    cursor = end;
  }

  return blocks;
}

function installBlock(content, block) {
  const blocks = findBlocks(content);
  if (blocks.length === 0) {
    const separator = content.length > 0 && !content.endsWith("\n") ? "\n" : "";
    return content + separator + block;
  }

  let result = content.slice(0, blocks[0].start) + block;
  let cursor = blocks[0].end;
  for (const duplicate of blocks.slice(1)) {
    result += content.slice(cursor, duplicate.start);
    cursor = duplicate.end;
  }
  return result + content.slice(cursor);
}

function removeBlocks(content) {
  const blocks = findBlocks(content);
  if (blocks.length === 0) return content;

  let result = "";
  let cursor = 0;
  for (const block of blocks) {
    result += content.slice(cursor, block.start);
    cursor = block.end;
  }
  return result + content.slice(cursor);
}

function nextBackupPath(soulPath, stamp) {
  const base = `${soulPath}.bak-${stamp}`;
  if (!fs.existsSync(base)) return base;
  let suffix = 1;
  while (fs.existsSync(`${base}-${suffix}`)) suffix += 1;
  return `${base}-${suffix}`;
}

function replaceFile(filePath, content, mode) {
  const temporaryPath = `${filePath}.tmp-${process.pid}`;
  fs.writeFileSync(temporaryPath, content, { flag: "wx" });
  if (mode !== undefined) fs.chmodSync(temporaryPath, mode);
  fs.renameSync(temporaryPath, filePath);
}

const action = valueAfter("--action");
const soulPath = path.resolve(valueAfter("--soul"));
const dryRun = process.argv.includes("--dry-run");
let soulEntry;
try {
  soulEntry = fs.lstatSync(soulPath);
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}
if (soulEntry?.isSymbolicLink()) {
  throw new Error(`Refusing to update symlinked coordinator SOUL: ${soulPath}`);
}
const exists = soulEntry !== undefined;
const current = exists ? fs.readFileSync(soulPath, "utf8") : "";
const mode = exists ? fs.statSync(soulPath).mode & 0o7777 : undefined;

if (action === "remove") {
  if (!exists) {
    process.stdout.write(`  ok (no coordinator SOUL file): ${soulPath}\n`);
    process.exit(0);
  }

  const next = removeBlocks(current);
  if (next === current) {
    process.stdout.write(`  ok (no managed coordinator activation): ${soulPath}\n`);
    process.exit(0);
  }
  if (dryRun) {
    process.stdout.write(`  would: remove managed coordinator activation from ${soulPath}\n`);
    process.exit(0);
  }

  replaceFile(soulPath, next, mode);
  process.stdout.write(`  removed managed coordinator activation: ${soulPath}\n`);
  process.exit(0);
}

if (action !== "install") throw new Error(`Unsupported action: ${action}`);

const blockPath = path.resolve(valueAfter("--block"));
const stamp = valueAfter("--stamp");
const block = fs.readFileSync(blockPath, "utf8");
const sourceBlocks = findBlocks(block);

if (
  sourceBlocks.length !== 1 ||
  sourceBlocks[0].start !== 0 ||
  sourceBlocks[0].end !== block.length ||
  !block.endsWith("\n")
) {
  throw new Error("Managed coordinator source must contain exactly one block and end with a newline");
}

const next = installBlock(current, block);

if (exists && next === current) {
  process.stdout.write(`  coordinator activation already current: ${soulPath}\n`);
  process.exit(0);
}

if (dryRun) {
  if (exists) process.stdout.write(`  would: back up ${soulPath}\n`);
  process.stdout.write(`  would: install coordinator activation in ${soulPath}\n`);
  process.exit(0);
}

fs.mkdirSync(path.dirname(soulPath), { recursive: true });
if (exists) {
  const backupPath = nextBackupPath(soulPath, stamp);
  fs.copyFileSync(soulPath, backupPath, fs.constants.COPYFILE_EXCL);
  process.stdout.write(`  backed up existing: ${soulPath} -> ${backupPath}\n`);
}

replaceFile(soulPath, next, mode);
process.stdout.write(`  installed coordinator activation: ${soulPath}\n`);
