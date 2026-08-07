import { lstat, readFile } from "node:fs/promises";
import { userInfo } from "node:os";
import { resolve } from "node:path";

const MAX_PROFILE_BYTES = 64 * 1024;

function cleanText(value, maxLength) {
  return String(value ?? "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}

function safeHandle(value) {
  const candidate = cleanText(value, 33)
    .replace(/^@/, "")
    .replace(/[^A-Za-z0-9_.-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 32);
  return /^[A-Za-z0-9_.-]{2,32}$/.test(candidate) ? candidate : "";
}

function ownedAndPrivate(stats, type) {
  const expectedType = type === "file" ? stats.isFile() : stats.isDirectory();
  return expectedType
    && !stats.isSymbolicLink()
    && (typeof process.getuid !== "function" || stats.uid === process.getuid())
    && (stats.mode & 0o022) === 0;
}

async function readLegacyProfile(persomeRoot) {
  const profileDirectory = resolve(persomeRoot, "who-am-i");
  const profilePath = resolve(profileDirectory, "profile.json");
  try {
    const [rootStats, directoryStats, profileStats] = await Promise.all([
      lstat(persomeRoot),
      lstat(profileDirectory),
      lstat(profilePath),
    ]);
    if (
      !ownedAndPrivate(rootStats, "directory")
      || !ownedAndPrivate(directoryStats, "directory")
      || !ownedAndPrivate(profileStats, "file")
      || profileStats.size > MAX_PROFILE_BYTES
    ) {
      return null;
    }
    const parsed = JSON.parse(await readFile(profilePath, "utf8"));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return null;
    }
    const displayName = cleanText(parsed.displayName, 64);
    if (!displayName) return null;
    return Object.freeze({
      displayName,
      handle: safeHandle(parsed.handle),
      tagline: cleanText(parsed.tagline, 120),
      description: cleanText(
        parsed.description || parsed.modelName,
        300,
      ),
      origin: "existing-personal-model",
    });
  } catch {
    return null;
  }
}

export async function existingPersonalModelProfile({
  persomeRoot,
  accountUsername = userInfo().username,
} = {}) {
  if (!persomeRoot || typeof persomeRoot !== "string") {
    throw new TypeError("A Personal Model root is required.");
  }
  const legacy = await readLegacyProfile(resolve(persomeRoot));
  if (legacy) return legacy;

  const displayName = cleanText(accountUsername, 64) || "You";
  return Object.freeze({
    displayName,
    handle: safeHandle(accountUsername),
    tagline: "Building a model of myself",
    description: "A Personal Model already on this Mac.",
    origin: "macos-account",
  });
}
