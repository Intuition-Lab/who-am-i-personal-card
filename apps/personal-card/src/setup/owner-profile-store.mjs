import { randomBytes } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const HANDLE_PATTERN = /^[A-Za-z0-9_.-]{2,32}$/;
const MODEL_ID_PATTERN = /^local-[a-f0-9]{20}$/;
const PROFILE_ORIGINS = new Set([
  "manual",
  "existing-personal-model",
  "macos-account",
]);

function cleanText(value, maxLength) {
  return String(value ?? "").trim().replace(/\s+/g, " ").slice(0, maxLength);
}
function defaultHandle(displayName, randomBytesFn) {
  const ascii = cleanText(displayName, 32)
    .toLowerCase()
    .replace(/[^a-z0-9_.-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 24);
  return HANDLE_PATTERN.test(ascii)
    ? ascii
    : `person-${Buffer.from(randomBytesFn(3)).toString("hex")}`;
}

function glyphFor(modelId) {
  const bytes = Buffer.from(modelId.replace(/^local-/, ""), "hex");
  return Array.from({ length: 25 }, (_, index) => {
    const byte = bytes[index % bytes.length];
    return ((byte >> (index % 8)) & 1) === 1;
  });
}

function assertProfile(profile) {
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) {
    throw new TypeError("Owner profile is invalid.");
  }
  if (
    profile.version !== 1
    || !MODEL_ID_PATTERN.test(profile.modelId)
    || !cleanText(profile.displayName, 64)
    || !HANDLE_PATTERN.test(profile.handle)
    || (profile.origin != null && !PROFILE_ORIGINS.has(profile.origin))
    || !Array.isArray(profile.glyph)
    || profile.glyph.length !== 25
    || profile.glyph.some((value) => typeof value !== "boolean")
  ) {
    throw new TypeError("Owner profile is invalid.");
  }
  return Object.freeze({
    ...profile,
    origin: profile.origin || "manual",
    glyph: Object.freeze([...profile.glyph]),
  });
}

export class OwnerProfileStore {
  constructor({
    dataDir,
    clock = () => Date.now(),
    randomBytesFn = randomBytes,
  }) {
    if (!dataDir || typeof dataDir !== "string") {
      throw new TypeError("OwnerProfileStore requires a data directory.");
    }
    if (typeof clock !== "function" || typeof randomBytesFn !== "function") {
      throw new TypeError("OwnerProfileStore dependencies are invalid.");
    }
    this.dataDir = resolve(dataDir);
    this.profilePath = resolve(this.dataDir, "owner-profile.json");
    this.clock = clock;
    this.randomBytesFn = randomBytesFn;
    this.current = null;
  }

  async load() {
    try {
      const raw = JSON.parse(await readFile(this.profilePath, "utf8"));
      this.current = assertProfile(raw);
      return this.current;
    } catch (error) {
      if (error?.code === "ENOENT") {
        this.current = null;
        return null;
      }
      throw new TypeError("Stored owner profile is invalid.");
    }
  }

  get() {
    return this.current;
  }

  async save(input) {
    const displayName = cleanText(input?.displayName, 64);
    if (!displayName) {
      const error = new Error("请输入你的名字");
      error.code = "PROFILE_NAME_REQUIRED";
      error.status = 400;
      throw error;
    }
    const requestedHandle = cleanText(input?.handle, 33).replace(/^@/, "");
    const handle = requestedHandle
      || this.current?.handle
      || defaultHandle(displayName, this.randomBytesFn);
    if (!HANDLE_PATTERN.test(handle)) {
      const error = new Error("用户名需要 2–32 位英文、数字、点、横线或下划线");
      error.code = "PROFILE_HANDLE_INVALID";
      error.status = 400;
      throw error;
    }

    const now = new Date(Number(this.clock())).toISOString();
    const modelId = this.current?.modelId
      || `local-${Buffer.from(this.randomBytesFn(10)).toString("hex")}`;
    const profile = assertProfile({
      version: 1,
      modelId,
      origin: this.current?.origin
        || (PROFILE_ORIGINS.has(input?.origin) ? input.origin : "manual"),
      displayName,
      handle,
      memberNumber: this.current?.memberNumber
        || String((Buffer.from(this.randomBytesFn(2)).readUInt16BE(0) % 999) + 1)
          .padStart(3, "0"),
      sinceYear: this.current?.sinceYear || new Date(Number(this.clock())).getFullYear(),
      tagline: cleanText(input?.tagline, 120)
        || this.current?.tagline
        || "Building a model of myself",
      description: cleanText(input?.description, 300)
        || this.current?.description
        || "A Personal Model that stays on this Mac.",
      publicUrl: this.current?.publicUrl || `local/${handle}`,
      material: this.current?.material || "graphite",
      glyph: this.current?.glyph || glyphFor(modelId),
      publiclyReadable: input?.publiclyReadable === true,
      createdAt: this.current?.createdAt || now,
      updatedAt: now,
    });

    await mkdir(this.dataDir, { recursive: true, mode: 0o700 });
    const temporaryPath = resolve(
      this.dataDir,
      `.owner-profile.${process.pid}.${Buffer.from(this.randomBytesFn(4)).toString("hex")}.tmp`,
    );
    await writeFile(
      temporaryPath,
      `${JSON.stringify(profile, null, 2)}\n`,
      { mode: 0o600 },
    );
    await rename(temporaryPath, this.profilePath);
    this.current = profile;
    return profile;
  }

  publicView() {
    const profile = this.current;
    if (!profile) return null;
    return Object.freeze({
      modelId: profile.modelId,
      displayName: profile.displayName,
      handle: `@${profile.handle}`,
      memberNumber: profile.memberNumber,
      sinceYear: profile.sinceYear,
      tagline: profile.tagline,
      description: profile.description,
      origin: profile.origin,
    });
  }
}
