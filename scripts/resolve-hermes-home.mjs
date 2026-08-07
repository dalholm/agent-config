#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

function canonicalizeCandidate(candidate) {
  const suffix = [];
  let existing = candidate;

  while (!fs.existsSync(existing)) {
    const parent = path.dirname(existing);
    if (parent === existing) break;
    suffix.unshift(path.basename(existing));
    existing = parent;
  }

  return path.resolve(fs.realpathSync(existing), ...suffix);
}

const home = path.resolve(process.env.HOME || os.homedir());
const hermesRoot = path.join(home, ".hermes");
const explicitHermesHome = Boolean(process.env.HERMES_HOME);
let candidate;

if (explicitHermesHome) {
  candidate = path.resolve(home, process.env.HERMES_HOME);
} else {
  candidate = hermesRoot;
  const activeProfileFile = path.join(hermesRoot, "active_profile");
  if (fs.existsSync(activeProfileFile)) {
    const profile = fs.readFileSync(activeProfileFile, "utf8").trim();
    if (profile !== "." && profile !== ".." && /^[A-Za-z0-9._-]+$/.test(profile)) {
      const profileHome = path.join(hermesRoot, "profiles", profile);
      if (fs.existsSync(profileHome) && fs.statSync(profileHome).isDirectory()) {
        candidate = profileHome;
      }
    }
  }
}

const canonicalHome = fs.realpathSync(home);
const resolved = canonicalizeCandidate(candidate);
const isStrictDescendant = resolved.startsWith(`${canonicalHome}${path.sep}`);
if (explicitHermesHome && !isStrictDescendant) {
  throw new Error(
    `Explicit HERMES_HOME must resolve below the current user's home: ${resolved}`,
  );
}
if (!explicitHermesHome && resolved !== canonicalHome && !isStrictDescendant) {
  throw new Error(`Hermes home must resolve under the current user's home: ${resolved}`);
}

process.stdout.write(resolved);
