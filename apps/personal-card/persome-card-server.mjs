import { createServer } from "node:http";
import { randomBytes } from "node:crypto";
import { spawn } from "node:child_process";
import { existsSync, lstatSync, readFileSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, extname, resolve, sep } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

import {
  createModelRequestContext,
  GrantTokenService,
  requireScope,
  SessionModelService,
  ViewerSessionStore,
} from "./src/auth/index.mjs";
import { ConnectorEventStore } from "./src/connectors/connector-event-store.mjs";
import { ConnectorSessionService } from "./src/connectors/connector-session-service.mjs";
import { ReportService } from "./src/connectors/report-service.mjs";
import { EvidenceService } from "./src/evidence/evidence-service.mjs";
import {
  buildGroundedAnswer,
  LocalPersomeContentBackend,
  normalizeSearchOptions,
} from "./src/content/personal-model-content-backend.mjs";
import { MINIMUM_SOURCE_REF_LENGTH } from "./src/contracts/personal-model-card.mjs";
import { LocalPersomeProvider } from "./src/providers/local-persome-provider.mjs";
import { ProviderRegistry } from "./src/providers/provider-registry.mjs";
import { OWNER_SCOPES } from "./src/auth/scope-policy.mjs";
import { existingPersonalModelProfile } from "./src/setup/existing-personal-model-profile.mjs";
import { OwnerProfileStore } from "./src/setup/owner-profile-store.mjs";
import { managedRuntimeIdentityMatches } from "./src/setup/runtime-identity.mjs";

const CARD_ROOT = dirname(fileURLToPath(import.meta.url));
const PRODUCT_VERSION = (() => {
  try {
    return readFileSync(resolve(CARD_ROOT, "product-version"), "utf8").trim()
      || "development";
  } catch {
    return "development";
  }
})();
const CARD_DATA_DIR = process.env.WHOAMI_CARD_DATA_DIR
  || resolve(homedir(), "Library/Application Support/Who Am I");
const CARD_FILE = "WhoAmI v5 · Persome Live.html";
const CARD_PORT = Number(process.env.WHOAMI_CARD_PORT || 8772);
const CARD_HOST = "127.0.0.1";
const PERSOME_MCP_URL = process.env.PERSOME_MCP_URL || "http://127.0.0.1:8742/mcp";
const WHO_AM_I_URL = process.env.WHO_AM_I_URL || "http://127.0.0.1:8788";
const PERSOME_CLI_OVERRIDE = process.env.PERSOME_CLI || "";
const COAST_CLI = process.env.COAST_CLI
  || resolve(homedir(), ".local/bin/coast");
const MCP_PROXY_PATH = resolve(CARD_ROOT, "whoami-mcp-proxy.mjs");
const PERSOME_SETUP_COMMAND = resolve(CARD_ROOT, "设置我的 Personal Model.command");
const RUNTIME_ROOT = resolve(CARD_DATA_DIR, "runtime");
const LIVE_CACHE_PATH = resolve(RUNTIME_ROOT, "live-cache.json");
const OBSERVABLE_MCP_NAME = "persome";
const LEGACY_OBSERVABLE_MCP_NAME = "whoami-personal-model";
const DEV_MODE = process.env.WHOAMI_DEV_MODE !== "0" && process.env.NODE_ENV !== "production";
const TEST_MODE = process.env.WHOAMI_TEST_MODE === "1";
const DEFAULT_PERSOME_TIMEOUT_MS = 20_000;
const SEARCH_PERSOME_TIMEOUT_MS = 180_000;
const GRANT_AUDIENCE = "personal-card-v5";
const GRANT_SECRET = process.env.WHOAMI_GRANT_SECRET || randomBytes(48);
const PERSOME_ROOT = process.env.PERSOME_ROOT || resolve(homedir(), ".persome");
const allowedCoastFrameIdsByModel = new Map();
const developmentModelRuntime = DEV_MODE
  ? (await import("./src/development/development-model-runtime.mjs"))
      .createDevelopmentModelRuntime()
  : null;
const ownerProfileStore = new OwnerProfileStore({ dataDir: CARD_DATA_DIR });
let ownerProfile = await ownerProfileStore.load();
let ownerProfileProvisionPromise = null;
const providerRegistry = new ProviderRegistry(
  developmentModelRuntime?.providers || {},
);
const viewerSessionStore = new ViewerSessionStore({
  cookieName: "whoami_card_session",
});
const grantTokenService = new GrantTokenService({
  secret: GRANT_SECRET,
  audience: GRANT_AUDIENCE,
});
const sessionModelService = new SessionModelService({
  sessionStore: viewerSessionStore,
  providerRegistry,
  grantTokenService,
  audience: GRANT_AUDIENCE,
  isOwner: async ({ modelId }) =>
    modelId === ownerProfile?.modelId
      || developmentModelRuntime?.isOwnerModel(modelId) === true,
  isPubliclyReadable: async ({ modelId }) =>
    modelId === ownerProfile?.modelId
      ? ownerProfile.publiclyReadable === true
      : developmentModelRuntime?.isPubliclyReadable(modelId) === true,
});
const connectorSessionService = new ConnectorSessionService();
const connectorEventStore = new ConnectorEventStore({
  sessionService: connectorSessionService,
  runtimeRoot: RUNTIME_ROOT,
});
const reportService = new ReportService({
  sessionService: connectorSessionService,
  eventStore: connectorEventStore,
});
const evidenceService = new EvidenceService({
  providerRegistry,
  sessionService: connectorSessionService,
  eventStore: connectorEventStore,
  loadCoastFrame: loadCoastFrameContent,
});
const activeConnectorSessions = new Map();

function findExecutable(name) {
  const candidates = [
    PERSOME_CLI_OVERRIDE,
    resolve(PERSOME_ROOT, "venv/bin", name),
    resolve(homedir(), ".local/bin", name),
    resolve(homedir(), ".cargo/bin", name),
    "/opt/homebrew/bin/" + name,
    "/usr/local/bin/" + name,
    ...String(process.env.PATH || "")
      .split(":")
      .filter(Boolean)
      .map((folder) => resolve(folder, name)),
  ].filter(Boolean);
  return candidates.find((candidate) => existsSync(candidate)) || "";
}

function resolvePersomeCli() {
  const managedCli = resolve(PERSOME_ROOT, "venv/bin/persome");
  if (TEST_MODE && PERSOME_CLI_OVERRIDE) return PERSOME_CLI_OVERRIDE;
  if (DEV_MODE) return PERSOME_CLI_OVERRIDE || findExecutable("persome");
  return managedRuntimeIdentityReady(managedCli)
    || existingRuntimeIdentityReady(managedCli)
    ? managedCli
    : "";
}

function secureOwnedFile(path) {
  try {
    const stats = lstatSync(path);
    return stats.isFile()
      && !stats.isSymbolicLink()
      && (typeof process.getuid !== "function" || stats.uid === process.getuid())
      && (stats.mode & 0o022) === 0;
  } catch {
    return false;
  }
}

function secureOwnedDirectory(path) {
  try {
    const stats = lstatSync(path);
    return stats.isDirectory()
      && !stats.isSymbolicLink()
      && (typeof process.getuid !== "function" || stats.uid === process.getuid())
      && (stats.mode & 0o022) === 0;
  } catch {
    return false;
  }
}

function existingRuntimeIdentityReady(cliPath) {
  const venvRoot = resolve(PERSOME_ROOT, "venv");
  const binRoot = resolve(venvRoot, "bin");
  try {
    const cliStats = lstatSync(cliPath);
    return secureOwnedDirectory(PERSOME_ROOT)
      && secureOwnedDirectory(venvRoot)
      && secureOwnedDirectory(binRoot)
      && secureOwnedFile(cliPath)
      && (cliStats.mode & 0o111) !== 0;
  } catch {
    return false;
  }
}

function managedRuntimeIdentityReady(cliPath) {
  const managementLock = resolve(PERSOME_ROOT, "product-management/runtime.lock");
  const externalReceipt = resolve(PERSOME_ROOT, "product-runtime.lock");
  const internalReceipt = resolve(PERSOME_ROOT, "venv/.product-runtime.lock");
  if (
    !secureOwnedFile(cliPath)
    || !secureOwnedFile(managementLock)
    || !secureOwnedFile(externalReceipt)
    || !secureOwnedFile(internalReceipt)
  ) {
    return false;
  }
  try {
    return managedRuntimeIdentityMatches({
      managementLockText: readFileSync(managementLock, "utf8"),
      externalReceiptText: readFileSync(externalReceipt, "utf8"),
      internalReceiptText: readFileSync(internalReceipt, "utf8"),
    });
  } catch {
    return false;
  }
}

function ownerProviderFor(profile) {
  const contentBackend = new LocalPersomeContentBackend({
    connectPersome,
    ownerAskUrl: WHO_AM_I_URL,
  });
  return new LocalPersomeProvider({
    modelIds: [profile.modelId],
    loadSnapshot: () => loadLocalOwnerSnapshot(profile),
    operations: {
      search: ({ modelId, query, options }) =>
        contentBackend.search({ modelId, query, options }),
      ask: ({ modelId, question, displayName, options }) =>
        contentBackend.ask({ modelId, question, displayName, options }),
      getEvidence: ({ modelId, reference }) =>
        contentBackend.getEvidence({ modelId, reference }),
      correct: async ({ modelId, correction }) => {
        const result = await writeLocalCorrection(correction);
        contentBackend.invalidate(modelId);
        return result;
      },
      resolveEvidence: async ({ modelId, reference }) =>
        resolveLocalEvidence(modelId, reference),
    },
  });
}

function registerOwnerProfile(profile) {
  providerRegistry.register(profile.modelId, ownerProviderFor(profile));
}

if (ownerProfile) registerOwnerProfile(ownerProfile);

async function ensureOwnerProfileForExistingModel({ allowAccountFallback }) {
  if (ownerProfile) return ownerProfile;
  if (!ownerProfileProvisionPromise) {
    ownerProfileProvisionPromise = (async () => {
      const detected = await existingPersonalModelProfile({
        persomeRoot: PERSOME_ROOT,
      });
      if (
        detected.origin === "macos-account"
        && allowAccountFallback !== true
      ) {
        return null;
      }
      const saved = await ownerProfileStore.save(detected);
      ownerProfile = saved;
      registerOwnerProfile(saved);
      return saved;
    })().finally(() => {
      ownerProfileProvisionPromise = null;
    });
  }
  return ownerProfileProvisionPromise;
}

function runLocalCommand(command, args, timeoutMs = 18000) {
  return new Promise((resolveCommand) => {
    const child = spawn(command, args, {
      stdio: ["ignore", "pipe", "pipe"],
      env: process.env,
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => child.kill("SIGTERM"), timeoutMs);
    child.stdout.on("data", (chunk) => { stdout = `${stdout}${chunk}`.slice(-12000); });
    child.stderr.on("data", (chunk) => { stderr = `${stderr}${chunk}`.slice(-12000); });
    child.on("error", (error) => {
      clearTimeout(timer);
      resolveCommand({ code: -1, stdout, stderr: error.message });
    });
    child.on("exit", (code) => {
      clearTimeout(timer);
      resolveCommand({ code: code ?? -1, stdout, stderr });
    });
  });
}

async function mcpTargetStatus(agent) {
  const command = agent === "codex" ? "codex" : "claude";
  const label = agent === "codex" ? "Codex" : "Claude Code";
  const iconUrl = agent === "codex" ? "/assets/app-icons/chatgpt.png" : "/assets/app-icons/claude.png";
  const configPath = agent === "codex"
    ? resolve(process.env.HOME || "", ".codex/config.toml")
    : resolve(process.env.HOME || "", ".claude.json");
  const configText = await readFile(configPath, "utf8").catch(() => "");
  let entry = "";
  if (agent === "codex") {
    entry = configText.match(/\[mcp_servers\.(?:"persome"|persome)\][\s\S]*?(?=\n\[|$)/)?.[0] || "";
  } else {
    try {
      const config = JSON.parse(configText);
      entry = JSON.stringify(config?.mcpServers?.persome || {});
    } catch {
      entry = "";
    }
  }
  const direct = !!entry && entry !== "{}";
  const observed = direct
    && entry.includes(MCP_PROXY_PATH)
    && entry.includes("--model")
    && entry.includes("--connector-session")
    && entry.includes("--grant");
  const installed = String(process.env.PATH || "")
    .split(":")
    .some((folder) => folder && existsSync(resolve(folder, command)));
  return {
    id: agent,
    name: label,
    iconUrl,
    installed,
    observed,
    direct,
    status: observed ? "可观察连接已接入" : direct ? "已有 Persome · 可开启观察" : "尚未接入",
  };
}

async function connectObservableMcpTarget(agent, binding = {}) {
  if (!agent) {
    const error = new Error("请选择 Claude Code 或 Codex");
    error.code = "CONNECTOR_REQUIRED";
    error.status = 400;
    throw error;
  }
  const status = await mcpTargetStatus(agent);
  if (status.observed) {
    return status;
  }
  await mkdir(RUNTIME_ROOT, { recursive: true });
  const configPath = agent === "codex"
    ? resolve(process.env.HOME || "", ".codex/config.toml")
    : resolve(process.env.HOME || "", ".claude.json");
  const previousConfig = await readFile(configPath, "utf8").catch(() => "");
  if (previousConfig) {
    const suffix = agent === "codex" ? "toml" : "json";
    await writeFile(resolve(RUNTIME_ROOT, `${agent}-config-before-observe.${suffix}`), previousConfig, "utf8");
  }
  const command = agent === "codex" ? "codex" : "claude";
  const removeArgs = agent === "codex"
    ? ["mcp", "remove", OBSERVABLE_MCP_NAME]
    : ["mcp", "remove", OBSERVABLE_MCP_NAME, "--scope", "user"];
  if (status.direct) {
    const removed = await runLocalCommand(command, removeArgs, 20000);
    if (removed.code !== 0) {
      throw new Error((removed.stderr || removed.stdout || "无法切换现有 Persome 连接").trim().slice(0, 800));
    }
  }
  const legacyEntry = agent === "codex"
    ? previousConfig.match(/\[mcp_servers\.whoami-personal-model\]/)
    : new RegExp(`"${LEGACY_OBSERVABLE_MCP_NAME}"\\s*:`).test(previousConfig);
  if (legacyEntry) {
    const legacyRemoveArgs = agent === "codex"
      ? ["mcp", "remove", LEGACY_OBSERVABLE_MCP_NAME]
      : ["mcp", "remove", LEGACY_OBSERVABLE_MCP_NAME, "--scope", "user"];
    await runLocalCommand(command, legacyRemoveArgs, 20000);
  }
  const proxyArgs = [
    process.execPath,
    MCP_PROXY_PATH,
    "--agent",
    agent,
    "--model",
    binding.modelId
      || ownerProfile?.modelId
      || developmentModelRuntime?.ownerModelId
      || "local-owner",
    "--connector-session",
    binding.sessionId || "cs_local_legacy",
    "--grant",
    binding.grantId || "owner_local_model",
    "--runtime-root",
    RUNTIME_ROOT,
    "--persome-root",
    PERSOME_ROOT,
  ];
  const args = agent === "codex"
    ? [
        "mcp", "add", OBSERVABLE_MCP_NAME,
        "--", ...proxyArgs,
      ]
    : [
        "mcp", "add", "--scope", "user",
        OBSERVABLE_MCP_NAME, "--", ...proxyArgs,
      ];
  const result = await runLocalCommand(command, args, 20000);
  if (result.code !== 0) {
    if (previousConfig) await writeFile(configPath, previousConfig, "utf8");
    throw new Error((result.stderr || result.stdout || "MCP 接入失败").trim().slice(0, 800));
  }
  return mcpTargetStatus(agent);
}

async function connectObservableMcp(req, res) {
  const body = await readJsonBody(req);
  const agent = body.agent === "codex"
    ? "codex"
    : body.agent === "claude-code"
      ? "claude-code"
      : "";
  sendJson(res, 200, {
    ok: true,
    target: await connectObservableMcpTarget(agent),
  });
}

const mimeTypes = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".md": "text/markdown; charset=utf-8",
  ".png": "image/png",
  ".webp": "image/webp",
  ".svg": "image/svg+xml; charset=utf-8",
};

class PersomeMcpClient {
  constructor(url) {
    this.url = url;
    this.sessionId = "";
    this.nextId = 1;
  }

  async initialize() {
    const result = await this.call("initialize", {
      protocolVersion: "2025-03-26",
      capabilities: {},
      clientInfo: { name: "who-am-i-v5-live", version: "1.1.0" },
    });
    await this.notify("notifications/initialized", {});
    return result;
  }

  callTool(name, args) {
    return this.call(
      "tools/call",
      { name, arguments: args },
      name === "search" ? SEARCH_PERSOME_TIMEOUT_MS : DEFAULT_PERSOME_TIMEOUT_MS,
    );
  }

  async notify(method, params) {
    await this.post({ jsonrpc: "2.0", method, params });
  }

  async call(method, params, timeoutMs = DEFAULT_PERSOME_TIMEOUT_MS) {
    const message = await this.post({
      jsonrpc: "2.0",
      id: this.nextId++,
      method,
      params,
    }, timeoutMs);
    if (message.error) throw new Error(message.error.message || `Persome 调用失败：${method}`);
    return message.result;
  }

  async post(payload, timeoutMs = DEFAULT_PERSOME_TIMEOUT_MS) {
    const headers = {
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
    };
    if (process.env.PERSOME_LOCAL_API_TOKEN) {
      headers.Authorization = `Bearer ${process.env.PERSOME_LOCAL_API_TOKEN}`;
    }
    if (this.sessionId) headers["mcp-session-id"] = this.sessionId;

    const response = await fetch(this.url, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const sessionId = response.headers.get("mcp-session-id");
    if (sessionId) this.sessionId = sessionId;
    const text = await response.text();
    if (!response.ok) throw new Error(text || `Persome HTTP ${response.status}`);
    if (!payload.id) return {};
    return parseMcpResponse(text);
  }

  close() {}
}

class PersomeStdioClient {
  constructor(command) {
    this.command = command;
    this.nextId = 1;
    this.pending = new Map();
    this.child = null;
    this.stderr = "";
  }

  start() {
    if (this.child) return;
    if (!this.command) throw new Error("没有找到本机 Persome");
    this.child = spawn(this.command, ["mcp"], {
      stdio: ["pipe", "pipe", "pipe"],
      env: { ...process.env, PYTHONUNBUFFERED: "1" },
    });
    this.child.stderr.on("data", (chunk) => {
      this.stderr = `${this.stderr}${chunk}`.slice(-2000);
    });
    this.child.on("error", (error) => this.rejectAll(error));
    this.child.on("exit", (code) => {
      if (this.pending.size) {
        this.rejectAll(new Error(this.stderr.trim() || `Persome 已退出 (${code})`));
      }
    });
    const lines = createInterface({ input: this.child.stdout });
    lines.on("line", (line) => {
      let message;
      try {
        message = JSON.parse(line);
      } catch {
        return;
      }
      if (message.id == null || !this.pending.has(message.id)) return;
      const pending = this.pending.get(message.id);
      this.pending.delete(message.id);
      clearTimeout(pending.timer);
      if (message.error) pending.reject(new Error(message.error.message || "Persome 调用失败"));
      else pending.resolve(message.result);
    });
  }

  rejectAll(error) {
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(error);
    }
    this.pending.clear();
  }

  async initialize() {
    this.start();
    const result = await this.call("initialize", {
      protocolVersion: "2025-03-26",
      capabilities: {},
      clientInfo: { name: "who-am-i-v5-live", version: "1.1.0" },
    });
    await this.notify("notifications/initialized", {});
    return result;
  }

  callTool(name, args) {
    return this.call(
      "tools/call",
      { name, arguments: args },
      name === "search" ? SEARCH_PERSOME_TIMEOUT_MS : DEFAULT_PERSOME_TIMEOUT_MS,
    );
  }

  notify(method, params) {
    this.start();
    this.child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method, params })}\n`);
    return Promise.resolve();
  }

  call(method, params, timeoutMs = DEFAULT_PERSOME_TIMEOUT_MS) {
    this.start();
    const id = this.nextId++;
    return new Promise((resolveCall, rejectCall) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        rejectCall(new Error(`Persome 调用超时：${method}`));
      }, timeoutMs);
      this.pending.set(id, { resolve: resolveCall, reject: rejectCall, timer });
      this.child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
    });
  }

  close() {
    if (!this.child) return;
    this.child.stdin.end();
    this.child.kill();
    this.child = null;
  }
}

async function connectPersome() {
  if (DEV_MODE && !TEST_MODE) {
    const httpClient = new PersomeMcpClient(PERSOME_MCP_URL);
    try {
      await httpClient.initialize();
      return httpClient;
    } catch {
      // Development may fall back to the same stdio path used by production.
    }
  }
  const stdioClient = new PersomeStdioClient(resolvePersomeCli());
  await stdioClient.initialize();
  return stdioClient;
}

function parseMcpResponse(text) {
  const trimmed = String(text || "").trim();
  if (!trimmed) return {};
  if (trimmed.startsWith("{")) return JSON.parse(trimmed);
  const data = trimmed
    .split(/\r?\n/)
    .filter((line) => line.startsWith("data:"))
    .map((line) => line.slice(5).trim())
    .filter(Boolean);
  if (!data.length) throw new Error("Persome 返回了无法识别的数据");
  return JSON.parse(data[data.length - 1]);
}

function getToolText(result) {
  if (result?.structuredContent?.result) return result.structuredContent.result;
  return result?.content?.find((item) => item.type === "text")?.text || "{}";
}

function parseToolJson(result) {
  const direct = result?.structuredContent?.result;
  if (direct && typeof direct === "object") return direct;
  const text = getToolText(result);
  try {
    return JSON.parse(text);
  } catch {
    return {};
  }
}

function cleanModelText(value, maxLength = 300) {
  const cleaned = String(value || "")
    .replace(/\s*[\(（]?⟨[^⟩]*⟩[\)）]?/g, "")
    .replace(/\s+/g, " ")
    .trim();
  if (cleaned.length <= maxLength) return cleaned;
  return `${cleaned.slice(0, maxLength - 1).trim()}…`;
}

function rootSummary(value) {
  const cleaned = cleanModelText(value, 900);
  const firstSentence = cleaned.match(/^.*?[.!?。！？](?:\s|$)/)?.[0]?.trim();
  return cleanModelText(firstSentence || cleaned, 360);
}

const APP_COLORS = {
  ChatGPT: "#10A37F",
  "Google Chrome": "#4285F4",
  Feishu: "#3370FF",
  "飞书": "#3370FF",
  Claude: "#D97757",
  WeChat: "#07C160",
  Cursor: "#1D1D1F",
  Figma: "#A259FF",
  Notion: "#1D1D1F",
  Terminal: "#55555C",
  Finder: "#4C9AFF",
};
const SKIP_APPS = new Set(["Unknown", "Window Server", "loginwindow", ""]);
const SENSITIVE_ACTIVITY =
  /authenticator|password|passkey|verification code|2-step|two-step|oauth|security page|security activity|recovery email|account security|device id|设备\s*id|设备id|验证码|两步验证|密码|登录验证|远程控制|uuremote/i;
const LOW_SIGNAL_ACTIVITY =
  /heartbeat|no visible (?:focused )?content|clicked within the .*interface|clicked (?:on )?.*dock icon|unspecified window|window was open and active|worked in window .*involving|general .*interface only|without dwelling on|no authored content|no further (?:content|activity)/i;
const LEISURE_ACTIVITY =
  /youtube|bilibili|哔哩哔哩|小红书|rednote|douyin|抖音|netflix|reddit|twitter|x\.com|steam|game|游戏|购物|淘宝|天猫|闲鱼|微博|music|音乐|spotify|photos?|照片/i;
const HUMAN_ACTIVITY =
  /微信|wechat|messages?|短信|mail|邮件|notes?|备忘录|music|音乐|spotify|photos?|照片|maps?|地图|calendar|日历|小红书|rednote|微博|购物/i;

function sanitizePrivateText(value, maxLength = 320) {
  let text = String(value || "")
    .replace(/[\u0000-\u001F\u007F-\u009F\uFFFD]/g, " ")
    .replace(/\s*—\s*raw:[\s\S]*$/i, "")
    .replace(/https?:\/\/\S+/gi, "[link]")
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, "[email]")
    .replace(/\/Users\/[^\s"'，。；;）)]+/g, "[local file]")
    .replace(/\b\d{3}\s+\d{3}\s+\d{3}\b/g, "[device id]")
    .replace(/\b[a-z0-9]{4}(?:\s+[a-z0-9]{4}){4,}\b/gi, "[private code]")
    .replace(/\b[A-Z0-9]{6,12}\b/g, (token) =>
      /\d/.test(token) && /[A-Z]/.test(token) ? "[private code]" : token,
    )
    .replace(/\s+/g, " ")
    .trim();
  if (text.length > maxLength) text = `${text.slice(0, maxLength - 1).trim()}…`;
  return text;
}

function conciseActivityText(value, apps = []) {
  const source = sanitizePrivateText(value, 1200)
    .replace(/^\s*(?:\[[^\]]+\]\s*)+/g, "")
    .replace(/\b(?:the )?user\b/gi, "")
    .replace(/\bInvolving:\s*[—-]\.?/gi, "")
    .replace(/\s+/g, " ")
    .trim();
  const appList = apps.filter(Boolean);
  if (/personal card|whoami|who am i|spotlight|proactive|rewind|persome|personal model/i.test(source)) {
    return "继续整理 Personal Card，并完善 Persome 的实时内容与 Rewind 回放。";
  }
  if (/融资|funding|financing|investor/i.test(source)) {
    return "继续整理融资材料与沟通内容。";
  }
  if (/campaign|PR\s*\+\s*直播|UGC|KOL|发布节奏|社媒/i.test(source)) {
    return "在飞书讨论发布节奏、社媒与 KOL 的配合。";
  }
  if (/cmux/i.test(source)) return "查看并研究 cmux 的产品与使用方式。";
  if (/image viewer|上一张|下一张|原始尺寸|zoom toolbar|查看图片/i.test(source)) {
    return "在飞书查看设计参考图。";
  }
  if (/figma|设计稿|design/i.test(source) || appList.includes("Figma")) {
    return "在 Figma 中继续整理设计稿。";
  }
  if (/微信|wechat|message|replied|reply/i.test(source) || appList.includes("WeChat")) {
    return "在微信查看并回复消息。";
  }
  if (/飞书|feishu|lark/i.test(source) || appList.includes("Feishu")) {
    return "在飞书继续处理文档与协作消息。";
  }
  if (/terminal|github|pull request|\bPR\b|code|debug/i.test(source) || appList.includes("Terminal")) {
    return "继续进行开发与调试。";
  }
  if (/chatgpt|codex|claude/i.test(source) || appList.some((app) => /ChatGPT|Claude/i.test(app))) {
    return "继续整理当前任务，并保留刚刚的上下文。";
  }
  if (/备忘录|notes?/i.test(source) || appList.includes("Notes")) {
    return "在备忘录中整理记录。";
  }
  if (/google chrome|browser|search|网页/i.test(source) || appList.includes("Google Chrome")) {
    return "在浏览器中查找并整理相关资料。";
  }
  const primary = appList[0];
  return primary ? `在 ${primary} 中继续处理当前任务。` : "继续处理当前任务。";
}

function cleanWindowTitle(value, app) {
  let text = sanitizePrivateText(value || app || "画面", 180)
    .replace(/[⠁-⣿✳◂]+/g, " ")
    .replace(/\s*[—-]\s*\d{2,4}\s*[×x]\s*\d{2,4}\s*$/i, "")
    .replace(/\s*[—-]\s*caffeinate\b[\s\S]*$/i, "")
    .replace(/\s+-\s+Google Chrome(?:\s+-\s+[^-]+)?$/i, "")
    .replace(/\s+/g, " ")
    .trim();
  if (/inbox\s*\(\d+\).*gmail/i.test(text)) return "Gmail · 收件箱";
  if (/data is ready for download.*gmail/i.test(text)) return "Gmail · 数据下载通知";
  if (/^无标题$/i.test(text)) return "浏览页面";
  if (/^微信(?:\s*\(窗口\))?$/i.test(text) || /^wechat$/i.test(text)) return "微信";
  if (/^朋友圈$/i.test(text)) return "微信 · 朋友圈";
  if (/^飞书(?:会议)?$/i.test(text)) return text;
  if (app === "Terminal") {
    const parts = text.split(/\s*[—-]\s*/).map((part) => part.trim()).filter(Boolean);
    const useful = parts.find((part) => /[\u4e00-\u9fff]/.test(part) && !/claude code|caffeinate/i.test(part));
    text = useful || parts.find((part) => !/claude code|caffeinate/i.test(part)) || "Terminal · 开发";
  }
  text = text
    .replace(/\s+-\s+Google 搜索/gi, " · Google 搜索")
    .replace(/\s+-\s+/g, " · ")
    .replace(/\s+/g, " ")
    .trim();
  if (!text || text === app) {
    if (/chatgpt/i.test(app || "")) return "当前对话";
    if (/claude/i.test(app || "")) return "当前任务";
    if (/chrome|safari|arc/i.test(app || "")) return "浏览页面";
    return app || "回放画面";
  }
  if (text.length > 72) text = `${text.slice(0, 71).trim()}…`;
  return text;
}

function dateKey(value) {
  const match = String(value || "").match(/\d{4}-\d{2}-\d{2}/);
  return match ? match[0] : "";
}

function minuteOfDay(value) {
  const match = String(value || "").match(/(?:T|\s)(\d{2}):(\d{2})/);
  return match ? Number(match[1]) * 60 + Number(match[2]) : 0;
}

function formatMinutes(value) {
  const minutes = Math.max(1, Math.round(Number(value) || 0));
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest ? `${hours}h ${rest}m` : `${hours}h`;
}

function rangeMinutes(value) {
  const match = String(value || "").match(/(\d{2}):(\d{2})\s*[–-]\s*(\d{2}):(\d{2})/);
  if (!match) return 1;
  const start = Number(match[1]) * 60 + Number(match[2]);
  const end = Number(match[3]) * 60 + Number(match[4]);
  return Math.max(1, end - start);
}

function titleFor(text, apps = []) {
  const source = String(text || "");
  if (/personal card|whoami|who am i|v5|v6|卡片/i.test(source)) return "Personal Card · 实时内容";
  if (/融资|funding|financing|investor/i.test(source)) return "融资 · 文档与沟通";
  if (/persome|personal model|personal me/i.test(source)) return "Persome · Personal Model";
  if (/飞书|feishu/i.test(source)) return "飞书 · 文档与协作";
  if (/figma/i.test(source)) return "Figma · 设计";
  if (/cmux/i.test(source)) return "cmux · 工具研究";
  if (/claude/i.test(source)) return "Claude · 工作流";
  if (/微信|wechat/i.test(source)) return "微信 · 消息";
  if (/chatgpt|codex/i.test(source)) return "ChatGPT · 当前任务";
  if (/备忘录|notes?/i.test(source)) return "备忘录 · 记录";
  if (/terminal|github|pull request/i.test(source)) return "开发 · 当前任务";
  if (/google chrome|browser|search/i.test(source)) return "浏览器 · 查找资料";
  return `${apps.filter(Boolean).slice(0, 2).join(" + ") || "最近活动"} · 当前任务`;
}

function appColor(name) {
  if (APP_COLORS[name]) return APP_COLORS[name];
  let hash = 0;
  for (const char of String(name || "")) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  const palette = ["#2B47E0", "#A259FF", "#0B8A6B", "#C1562B", "#137A8C", "#6E5AA8"];
  return palette[hash % palette.length];
}

function canonicalApp(name) {
  const value = String(name || "");
  if (/claude/i.test(value)) return "Claude";
  if (/chatgpt|codex/i.test(value)) return "ChatGPT";
  if (/google chrome|chrome|browser/i.test(value)) return "Chrome";
  if (/wechat|微信/i.test(value)) return "WeChat";
  if (/feishu|飞书|lark/i.test(value)) return "Lark";
  if (/coast/i.test(value)) return "Coast";
  if (/notes|备忘录/i.test(value)) return "Notes";
  if (/terminal/i.test(value)) return "Terminal";
  if (/finder/i.test(value)) return "Finder";
  return value || "Other";
}

function shortTopic(value) {
  return String(value || "")
    .replace(/\s*·\s*(?:实时内容|当前任务|工作流|消息|查找资料)$/i, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 34);
}

function durationSeconds(value) {
  const text = String(value || "");
  const hours = Number(text.match(/(\d+)\s*h/)?.[1] || 0);
  const minutes = Number(text.match(/(\d+)\s*m/)?.[1] || 0);
  const seconds = Number(text.match(/(\d+)\s*s/)?.[1] || 0);
  return Math.max(2, hours * 3600 + minutes * 60 + seconds);
}

function runCoast(args, timeoutMs = 12000) {
  return new Promise((resolveRun, rejectRun) => {
    if (!existsSync(COAST_CLI)) {
      rejectRun(new Error("Coast CLI 不可用"));
      return;
    }
    const child = spawn(COAST_CLI, args, { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "", stderr = "", size = 0;
    const timer = setTimeout(() => {
      child.kill();
      rejectRun(new Error("Coast 查询超时"));
    }, timeoutMs);
    child.stdout.on("data", (chunk) => {
      size += chunk.length;
      if (size > 12 * 1024 * 1024) {
        child.kill();
        clearTimeout(timer);
        rejectRun(new Error("Coast 返回内容过大"));
        return;
      }
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => { stderr = `${stderr}${chunk}`.slice(-4000); });
    child.on("error", (error) => {
      clearTimeout(timer);
      rejectRun(error);
    });
    child.on("exit", (code) => {
      clearTimeout(timer);
      if (code === 0) resolveRun({ stdout, stderr });
      else rejectRun(new Error(stderr.trim() || `Coast 已退出 (${code})`));
    });
  });
}

async function coastFramesForDay(key) {
  try {
    const { stdout } = await runCoast([
      "query", "cover", "--tr", key,
      "--min-difference-text", "0.3",
      "--min-difference-seconds", "60",
      "--json",
    ]);
    const parsed = JSON.parse(stdout);
    const frames = (Array.isArray(parsed?.frames) ? parsed.frames : [])
      .map((frame) => {
        const searchable = `${frame?.application || ""} ${frame?.title || ""} ${frame?.ocr_text || ""}`;
        if (!frame?.frame_id || SENSITIVE_ACTIVITY.test(searchable)) return null;
        const timestamp = String(frame.timestamp || "");
        return {
          id: Number(frame.frame_id),
          timestamp,
          time: timestamp.slice(11, 16),
          app: sanitizePrivateText(frame.application || "Unknown", 36),
          title: cleanWindowTitle(frame.title || frame.application || "画面", frame.application),
          duration: 60,
          color: appColor(frame.application),
        };
      })
      .filter(Boolean)
      .sort((a, b) => a.timestamp.localeCompare(b.timestamp));
    frames.forEach((frame, index) => {
      const next = frames[index + 1];
      if (!next) return;
      const seconds = Math.round((Date.parse(next.timestamp) - Date.parse(frame.timestamp)) / 1000);
      frame.duration = Number.isFinite(seconds) ? Math.max(2, Math.min(600, seconds)) : 60;
    });
    if (frames.length <= 48) return frames;
    const stride = (frames.length - 1) / 47;
    return Array.from({ length: 48 }, (_, index) => frames[Math.round(index * stride)]);
  } catch {
    return [];
  }
}

function secureCoastImagePath(value) {
  const imagePath = resolve(String(value || ""));
  const imageRoot = resolve("/tmp/coast-cli");
  if (
    !imagePath.startsWith(`${imageRoot}${sep}`)
    || extname(imagePath).toLowerCase() !== ".png"
  ) {
    return "";
  }
  try {
    const file = lstatSync(imagePath);
    return file.isFile() && !file.isSymbolicLink() ? imagePath : "";
  } catch {
    return "";
  }
}

async function loadCoastFrameContent({ frameId }) {
  const { stdout } = await runCoast([
    "query", "image", "--id", String(frameId), "--crop",
  ], 15000);
  const imagePath = secureCoastImagePath(stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find(Boolean) || "");
  if (!imagePath) return null;
  return { imagePath };
}

async function attachCoastFrames(live, modelId = ownerProfile?.modelId || "local-owner") {
  const allowedFrameIds = allowedCoastFrameIdsByModel.get(modelId) || new Set();
  allowedCoastFrameIdsByModel.set(modelId, allowedFrameIds);
  const days = Array.isArray(live?.days) ? live.days.slice(0, 7) : [];
  const results = await Promise.all(days.map((day) => coastFramesForDay(day.key)));
  days.forEach((day, index) => {
    day.coastFrames = results[index];
    results[index].forEach((frame) => allowedFrameIds.add(String(frame.id)));
    day.coastSource = results[index].length
      ? `Coast · ${results[index].length} 个代表画面`
      : "Coast · 当天没有可用画面";
  });
  const coastFrames = results.flat();
  if (coastFrames.length) {
    live.connectors = [
      {
        name: "Coast",
        app: "Coast",
        on: true,
        usageTime: `${coastFrames.length} frames`,
        cites: `${coastFrames.length} 个代表画面`,
        revs: coastFrames.slice(-3).reverse().map((frame) => ({
          t: frame.time,
          rc: "FRAME",
          x: `${frame.app} · ${frame.title}`,
        })),
      },
      ...(Array.isArray(live.connectors) ? live.connectors.filter((connector) => connector.name !== "Coast") : []),
    ];
  }
  return live;
}

function parseActivityEntry(entry) {
  const content = String(entry?.content || "");
  if (!content || SENSITIVE_ACTIVITY.test(content)) return null;
  const key = dateKey(entry?.path) || dateKey(entry?.timestamp);
  if (!key) return null;
  const range = content.match(/\((\d{2}:\d{2}\s*[–-]\s*\d{2}:\d{2})\)/)?.[1] || "";
  const paragraphs = content.split(/\n\s*\n/).map((part) => part.trim()).filter(Boolean);
  const bulletMatches = [...content.matchAll(
    /^-\s+\[(\d{2}:\d{2}\s*[–-]\s*\d{2}:\d{2}),\s*([^\]]+)\]\s*(.+)$/gm,
  )];
  const apps = [...new Set(bulletMatches.map((match) => match[2].trim()).filter((app) => !SKIP_APPS.has(app)))];
  const rawSummary = sanitizePrivateText(paragraphs[1] || "", 900);
  if (!rawSummary || SENSITIVE_ACTIVITY.test(rawSummary) || LOW_SIGNAL_ACTIVITY.test(rawSummary)) return null;
  const summary = conciseActivityText(rawSummary, apps);
  const appMinutes = {};
  for (const match of bulletMatches) {
    const app = match[2].trim();
    if (SKIP_APPS.has(app) || SENSITIVE_ACTIVITY.test(match[3])) continue;
    appMinutes[app] = (appMinutes[app] || 0) + rangeMinutes(match[1]);
  }
  const start = range.match(/^(\d{2}:\d{2})/)?.[1] || String(entry?.timestamp || "").slice(11, 16);
  return {
    key,
    start: start || "—",
    minute: start ? Number(start.slice(0, 2)) * 60 + Number(start.slice(3, 5)) : 0,
    duration: rangeMinutes(range),
    title: titleFor(summary, apps),
    io: `${apps.slice(0, 3).join(" + ") || "Persome"} · ${range || "recent"}`,
    detail: summary,
    frames: bulletMatches.slice(0, 4).map((match) => match[1].slice(0, 5)),
    apps,
    appMinutes,
    sourceId: String(entry?.id || ""),
  };
}

function parseCurrentBlock(block) {
  const entries = (Array.isArray(block?.entries) ? block.entries : [])
    .map((entry) => sanitizePrivateText(entry, 900))
    .filter((entry) => entry && !SENSITIVE_ACTIVITY.test(entry) && !LOW_SIGNAL_ACTIVITY.test(entry));
  const apps = (Array.isArray(block?.apps_used) ? block.apps_used : [])
    .filter((app) => !SKIP_APPS.has(app));
  if (!entries.length || !apps.length) return null;
  const key = dateKey(block.start_time);
  if (!key) return null;
  const start = String(block.start_time || "").slice(11, 16);
  const duration = Math.max(
    1,
    Math.round((new Date(block.end_time).getTime() - new Date(block.start_time).getTime()) / 60000) || 1,
  );
  const detail = conciseActivityText(entries.join(" "), apps);
  if (!detail || SENSITIVE_ACTIVITY.test(detail)) return null;
  const appMinutes = Object.fromEntries(apps.map((app) => [app, duration]));
  return {
    key,
    start,
    minute: minuteOfDay(block.start_time),
    duration,
    title: titleFor(detail, apps),
    io: `${apps.slice(0, 3).join(" + ")} · 实时活动`,
    detail,
    frames: [start],
    apps,
    appMinutes,
    sourceId: `live-${block.start_time}`,
    live: true,
  };
}

function dayTitle(key) {
  const date = new Date(`${key}T12:00:00`);
  return new Intl.DateTimeFormat("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
  }).format(date);
}

function shortDay(key) {
  const date = new Date(`${key}T12:00:00`);
  return new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric" })
    .format(date)
    .toUpperCase();
}

function localDayKey(date) {
  return [
    date.getFullYear(),
    String(date.getMonth() + 1).padStart(2, "0"),
    String(date.getDate()).padStart(2, "0"),
  ].join("-");
}

function compactDayEvents(rawEvents) {
  const compacted = [];
  for (const original of [...rawEvents].sort((a, b) => a.minute - b.minute)) {
    const event = {
      ...original,
      apps: [...(original.apps || [])],
      appMinutes: { ...(original.appMinutes || {}) },
      frames: [...(original.frames || [])],
      lastMinute: original.minute,
    };
    const previous = compacted.at(-1);
    const sameTask = previous &&
      previous.title === event.title &&
      previous.detail === event.detail &&
      event.minute - previous.lastMinute <= 20;
    if (!sameTask) {
      compacted.push(event);
      continue;
    }
    previous.duration += event.duration;
    previous.lastMinute = event.minute;
    previous.apps = [...new Set([...previous.apps, ...event.apps])];
    for (const [app, minutes] of Object.entries(event.appMinutes)) {
      previous.appMinutes[app] = (previous.appMinutes[app] || 0) + minutes;
    }
    previous.frames = [...previous.frames, ...event.frames].slice(-4);
    previous.io = `${previous.apps.slice(0, 3).join(" + ")} · ${previous.start}–${event.start}`;
  }
  return compacted;
}

function buildLivePayload(activity, current) {
  const activityEntries = (Array.isArray(activity?.entries) ? activity.entries : [])
    .map(parseActivityEntry)
    .filter(Boolean);
  const currentEvents = (Array.isArray(current?.recent_timeline_blocks)
    ? current.recent_timeline_blocks
    : [])
    .map(parseCurrentBlock)
    .filter(Boolean);
  const merged = [...currentEvents.reverse(), ...activityEntries];
  const deduped = [];
  const seen = new Set();
  for (const event of merged) {
    const signature = `${event.key}|${event.start}|${event.title}`;
    if (seen.has(signature)) continue;
    seen.add(signature);
    deduped.push(event);
  }

  const groups = new Map();
  for (const event of deduped) {
    if (!groups.has(event.key)) groups.set(event.key, []);
    groups.get(event.key).push(event);
  }
  const days = [...groups.entries()]
    .sort(([a], [b]) => b.localeCompare(a))
    .slice(0, 14)
    .map(([key, rawEvents]) => {
      const allEvents = compactDayEvents(rawEvents);
      const events = allEvents.slice(-8);
      const appTotals = {};
      for (const event of allEvents) {
        for (const [app, minutes] of Object.entries(event.appMinutes || {})) {
          appTotals[app] = (appTotals[app] || 0) + minutes;
        }
      }
      const apps = Object.entries(appTotals)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 5);
      const totalMinutes = Math.max(
        allEvents.reduce((sum, event) => sum + event.duration, 0),
        apps.reduce((sum, [, minutes]) => sum + minutes, 0),
      );
      const leisureEvents = allEvents.filter((event) =>
        LEISURE_ACTIVITY.test(`${event.title} ${event.detail} ${event.apps.join(" ")}`),
      );
      const leisureMinutes = leisureEvents.reduce((sum, event) => sum + event.duration, 0);
      const humanEvents = allEvents.filter((event) =>
        HUMAN_ACTIVITY.test(`${event.title} ${event.detail} ${event.apps.join(" ")}`),
      );
      const humanApps = [...new Set(humanEvents
        .flatMap((event) => event.apps)
        .filter((app) => HUMAN_ACTIVITY.test(app))
        .map(canonicalApp))]
        .filter(Boolean)
        .slice(0, 3);
      const moments = [];
      const momentSeen = new Set();
      for (const event of allEvents) {
        const topic = shortTopic(event.title);
        const signature = topic.toLowerCase().replace(/[\s·，。:：\-—_]+/g, "");
        if (!topic || momentSeen.has(signature)) continue;
        momentSeen.add(signature);
        moments.push(topic);
      }
      const latest = events.at(-1);
      const narrative = moments.length
        ? `这一天从「${moments[0]}」开始${moments.length > 1 ? `，后来转到「${moments[Math.min(1, moments.length - 1)]}」` : ""}${moments.length > 2 ? `，最后停在「${moments.at(-1)}」` : ""}。注意力主要在 ${apps.slice(0, 2).map(([app]) => canonicalApp(app)).join(" 与 ") || "少量活动"}。`
        : "这一天留下的活动还很少，暂时不足以描述完整节奏。";
      const humanNote = humanEvents.length
        ? `工作之外，也留下了 ${humanApps.join("、") || "日常应用"} 的 ${humanEvents.length} 个生活片段。`
        : "这一天几乎都留在工作里，没有记录到明显的生活片段。";
      const readingSource = `${moments.join(" ")} ${allEvents.map((event) => `${event.title} ${event.detail}`).join(" ")}`;
      const readingTitle = /设计|卡片|界面|文案|spec|prd|边界|访客|权限|personal card|who am i/i.test(readingSource)
        ? "边界的编辑者"
        : /修复|代码|开发|根因|脚本|database|数据库|terminal|codex/i.test(readingSource)
          ? "根因的追问者"
          : /会议|沟通|消息|微信|feishu|lark|mail|邮件/i.test(readingSource)
            ? "关系里的校准者"
            : moments.length
              ? "把模糊变清楚的人"
              : "把一天读回来的人";
      const readingStatement = readingTitle === "边界的编辑者"
        ? "你今天反复做的，不是把东西补全，而是决定什么不该被放进去。"
        : readingTitle === "根因的追问者"
          ? "你不是在追求最快地结束问题，而是在避免同一件事换个样子回来。"
          : readingTitle === "关系里的校准者"
            ? "你今天的很多判断发生在人与信息之间：既想把话说清，也在保护关系不被过度解释。"
            : "你不是在把一天塞满，而是在把一件仍然含糊的事带回眼前，直到它拥有更准确的形状。";
      const mainMoment = moments[0] || latest?.title || "今天留下的片段";
      const lastMoment = moments.at(-1) || mainMoment;
      const primaryApps = apps.slice(0, 2).map(([app]) => canonicalApp(app)).filter(Boolean);
      const firstEvidence = events[0];
      const middleEvidence = events[Math.min(1, Math.max(0, events.length - 1))];
      const lastEvidence = events.at(-1);
      const readingEvidence = [
        {
          text: moments.length > 1
            ? `你不是把时间填满，而是在「${mainMoment}」与「${lastMoment}」之间反复校准一件仍在成形的事。`
            : `你在「${mainMoment}」上停留了下来；它不是随手路过的主题。`,
          receipt: firstEvidence?.sourceId || `rewind_${key}_01`,
        },
        {
          text: primaryApps.length > 1
            ? `你换了 ${primaryApps.join(" 和 ")}，却没有真正换问题：工具在变，注意力仍指向同一处。`
            : `你今天没有急着把注意力铺开，而是把它留给了少数几件事。`,
          receipt: middleEvidence?.sourceId || firstEvidence?.sourceId || `rewind_${key}_02`,
        },
        {
          text: leisureMinutes > 0
            ? `你允许自己离开工作 ${formatMinutes(leisureMinutes)}；那不是空白，也是今天真实的呼吸。`
            : humanEvents.length
              ? `工作之外仍有 ${humanEvents.length} 个生活片段穿过这一天，你没有完全消失在任务里。`
              : `这一天几乎只留下工作痕迹；专注是真的，生活被挤薄也是真的。`,
          receipt: lastEvidence?.sourceId || firstEvidence?.sourceId || `rewind_${key}_03`,
        },
      ];
      const readingTension = leisureMinutes > 0
        ? "你想把一件事做深，也没有彻底剥夺自己离开的权利。它们并不矛盾，但目前还不足以说明这是不是你稳定的节奏。"
        : humanEvents.length
          ? "你一边把事情推向更清楚，一边保留了少量与人的连接。今天看得见这种拉力，还不能替你定义它。"
          : "你把很多注意力给了手上的事。这可以叫专注，也可能只是今天太窄；证据还不够，我先不替你选答案。";
      const dailyLetter = [
        `给 ${Number(key.slice(5, 7))} 月 ${Number(key.slice(8, 10))} 日的你：`,
        moments.length
          ? `我看见你今天几次回到「${mainMoment}」。真正像你的，也许不是做完了什么，而是你不肯让它停在含糊里。`
          : "今天留下的记录不多。少并不等于没有发生，我先替你把这点空白也留着。",
        leisureMinutes > 0
          ? "你离开过一会儿，又回来。那段没有产出的时间，也属于完整的你。"
          : humanEvents.length
            ? "那些很短的生活片段没有打断这一天，反而让它不像一张只有工作的履历。"
            : "明天不需要证明今天是对的。先承认你确实这样度过了一天，就够了。",
      ];
      return {
        key,
        n: Number(key.slice(-2)),
        title: dayTitle(key),
        short: shortDay(key),
        peek: latest?.title || "Persome · live",
        portrait: apps.length
          ? `这一天的注意力主要在 ${apps.slice(0, 3).map(([app]) => app).join("、")} 之间流动。`
          : "Persome 已经记录下这一天。",
        taught: `Persome · ${events.length} 个实时活动段`,
        narr: narrative,
        lit: [5, 18],
        totalTime: formatMinutes(totalMinutes),
        observation: {
          recordedTime: formatMinutes(totalMinutes),
          leisureTime: leisureMinutes > 0 ? formatMinutes(leisureMinutes) : "0m",
          leisureNote: leisureMinutes > 0
            ? `${leisureEvents.length} 个明确的休息或娱乐片段。`
            : "没有发现能明确归类为休息或娱乐的片段。",
          switches: Math.max(0, allEvents.length - 1),
          focusNote: apps.length
            ? `主要在 ${apps.slice(0, 2).map(([app]) => canonicalApp(app)).join(" 与 ")}。`
            : "今天的活动还很少。",
          humanNote,
          takeaway: leisureMinutes > 0
            ? "你并不是一直在向前冲；停下来也是这一天真实的一部分。"
            : humanEvents.length
              ? "工作和生活短暂地交错过，这些小片段也值得留下。"
              : "这一天很集中，也很单一；Rewind 只是把这个事实安静地放在这里。",
        },
        selfReading: {
          title: readingTitle,
          statement: readingStatement,
          verified: readingEvidence,
          tension: readingTension,
          letter: dailyLetter,
        },
        letter: dailyLetter.join("\n"),
        apps: apps.map(([app, minutes]) => [app, appColor(app), formatMinutes(minutes)]),
        tl: events.map((event, index) => ({
          w: Math.max(1, event.duration),
          c: appColor(event.apps[0]),
          ev: index,
          tip: `${event.start} · ${event.title}`,
        })),
        events: events.map((event) => ({
          t: event.start,
          title: event.title,
          io: event.io,
          detail: event.detail,
          frames: event.frames.length ? event.frames : [event.start],
          sourceId: event.sourceId,
        })),
        source: "Persome · current_context + recent_activity",
      };
    });

  const allApps = {};
  for (const day of days) {
    for (const [app, , duration] of day.apps) {
      const match = duration.match(/(?:(\d+)h)?\s*(?:(\d+)m)?/);
      const minutes = (Number(match?.[1]) || 0) * 60 + (Number(match?.[2]) || 0);
      allApps[app] = (allApps[app] || 0) + minutes;
    }
  }
  const apps = Object.entries(allApps)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 6)
    .map(([name, minutes]) => ({
      name,
      icon: name.slice(0, 1).toUpperCase(),
      color: appColor(name),
      time: formatMinutes(minutes),
      day: days.find((day) => day.apps.some(([app]) => app === name))?.key || days[0]?.key || "",
    }));
  const connectorGroups = new Map();
  for (const event of deduped) {
    for (const rawApp of event.apps || []) {
      const name = canonicalApp(rawApp);
      if (!name || name === "Other") continue;
      if (!connectorGroups.has(name)) connectorGroups.set(name, { name, minutes: 0, events: [] });
      const group = connectorGroups.get(name);
      group.minutes += Number(event.appMinutes?.[rawApp] || event.duration || 1);
      if (!group.events.some((item) => item.key === event.key && item.title === event.title)) {
        group.events.push(event);
      }
    }
  }
  const connectors = [...connectorGroups.values()]
    .sort((a, b) => b.minutes - a.minutes)
    .slice(0, 8)
    .map((group) => ({
      name: group.name,
      app: group.name,
      on: group.minutes > 0,
      usageTime: formatMinutes(group.minutes),
      cites: `${formatMinutes(group.minutes)} · 最近活动`,
      revs: group.events
        .sort((a, b) => `${b.key} ${b.start}`.localeCompare(`${a.key} ${a.start}`))
        .slice(0, 3)
        .map((event) => ({
          t: event.start,
          rc: shortDay(event.key),
          x: `${shortTopic(event.title)}${event.detail ? ` · ${String(event.detail).slice(0, 64)}` : ""}`,
        })),
    }));

  const proactiveSource = deduped
    .filter((event) => event.live || event.key === days[0]?.key)
    .filter((event, index, list) => list.findIndex((item) => item.title === event.title) === index)
    .slice(0, 3);
  const proactive = proactiveSource.map((event, index) => ({
    t: event.start,
    title: `${index === 0 ? "继续" : index === 1 ? "回看" : "接上"} · ${event.title}`,
    why: `${String(event.detail || "").replace(/[。.]$/, "")} · ${event.apps.slice(0, 2).join(" + ") || "Persome"}`,
    day: event.key,
  }));
  const now = new Date();
  const tomorrow = new Date(now);
  tomorrow.setDate(now.getDate() + 1);
  const todayKey = localDayKey(now);
  const tomorrowKey = localDayKey(tomorrow);
  const continueEvent = proactiveSource[0] || deduped[0] || null;
  const rewindEvent = proactiveSource[1]
    || deduped.find((event) => event.title !== continueEvent?.title || event.key !== continueEvent?.key)
    || proactiveSource[0]
    || deduped[0]
    || null;
  const taskTopic = String(continueEvent?.title || days[0]?.peek || "当前任务")
    .replace(/\s*·\s*(?:实时内容|当前任务|工作流)$/i, "")
    .trim();
  const futureEvents = [
    {
      id: `future-${tomorrowKey}-morning`,
      day: tomorrowKey,
      dateTitle: dayTitle(tomorrowKey),
      when: "明天",
      time: "09:30",
      title: `回到 ${taskTopic || "今天尚未结束的事"}`,
      detail: "从今天留下的上下文开始，不必重新想起一切。",
      confidence: "很可能",
      app: continueEvent?.apps?.[0] || "Notes",
    },
    {
      id: `future-${tomorrowKey}-afternoon`,
      day: tomorrowKey,
      dateTitle: dayTitle(tomorrowKey),
      when: "明天",
      time: "14:00",
      title: "把尚未说清楚的地方写下来",
      detail: "关键决定、仍不确定的地方，可能会在下午重新浮现。",
      confidence: "也许",
      app: "Notes",
    },
    {
      id: `future-${tomorrowKey}-evening`,
      day: tomorrowKey,
      dateTitle: dayTitle(tomorrowKey),
      when: "明天",
      time: "18:30",
      title: "在离开前，记住今天最重要的一件事",
      detail: "给一天留下一个可以回来的入口，而不是另一项待办。",
      confidence: "留白",
      app: "Notes",
    },
  ];
  const nowItems = [
    {
      kind: "过去",
      t: rewindEvent?.start || "—",
      title: `${rewindEvent?.key ? Number(rewindEvent.key.slice(5, 7)) + " 月 " + Number(rewindEvent.key.slice(8, 10)) + " 日" : "最近"}，${shortTopic(rewindEvent?.title) || "发生了什么"}`,
      why: "回到一个差点被忘记的片段",
      day: rewindEvent?.key || days[0]?.key || todayKey,
      app: rewindEvent?.apps?.[0] || "Coast",
    },
    {
      kind: "现在",
      t: continueEvent?.start || "NOW",
      title: `继续 ${shortTopic(continueEvent?.title) || "刚才的事"}`,
      why: "从刚才留下的上下文开始",
      day: continueEvent?.key || days[0]?.key || todayKey,
      app: continueEvent?.apps?.[0] || "ChatGPT",
    },
    {
      kind: "未来",
      t: "明天",
      title: futureEvents[0].title,
      why: "先替你整理上下文、材料与未完成项",
      day: futureEvents[0].day,
      futureId: futureEvents[0].id,
      app: futureEvents[0].app,
    },
  ];
  const firstDay = days[0];
  return {
    generatedAt: now.toISOString(),
    clockLabel: new Intl.DateTimeFormat("en-GB", {
      weekday: "short",
      day: "numeric",
      month: "short",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).format(now),
    monthLabel: new Intl.DateTimeFormat("en-US", { month: "long" }).format(now),
    yearLabel: String(now.getFullYear()),
    proactiveLabel: `${new Intl.DateTimeFormat("en-US", { weekday: "short" }).format(now).toUpperCase()} ${now.getMonth() + 1}/${now.getDate()} · LIVE`,
    proactive,
    nowItems,
    futureEvents,
    pushes: proactive.slice(0, 2).map((item, index) => ({
      text: item.title,
      sub: `${item.t} · ${item.why}`,
      day: item.day,
      delay: index ? ".45s" : ".15s",
    })),
    observation: firstDay
      ? `观察：今天最近的注意力在「${firstDay.peek}」——点开看 Persome 的实时活动段`
      : "观察：Persome 已连接，等待新的活动段。",
    days,
    apps,
    connectors,
    themes: apps.map((app, index) => ({
      label: app.name,
      sub: `${app.time} · live`,
      day: app.day,
      color: app.color,
      rank: index,
    })),
  };
}

function allowedRequest(req) {
  const origin = String(req.headers.origin || "");
  return !origin || origin === `http://${CARD_HOST}:${CARD_PORT}` || origin === `http://localhost:${CARD_PORT}`;
}

function viewerSessionFor(req, res) {
  const result = viewerSessionStore.getOrCreateFromCookie(req.headers.cookie || "");
  if (result.setCookie) res.whoamiSetCookie = result.setCookie;
  return result.session;
}

async function readJsonBody(req, maxBytes = 16 * 1024) {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > maxBytes) throw new Error("输入内容太长");
    chunks.push(chunk);
  }
  const text = Buffer.concat(chunks).toString("utf8");
  return text ? JSON.parse(text) : {};
}

function sendJson(res, status, body) {
  const headers = {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
  };
  if (res.whoamiSetCookie) headers["Set-Cookie"] = res.whoamiSetCookie;
  res.writeHead(status, headers);
  res.end(JSON.stringify(body));
}

function sendError(res, status, error) {
  const safeStatus = Number.isInteger(error?.status) ? error.status : status;
  const safeCode = typeof error?.code === "string"
    ? error.code
    : "PERSONAL_MODEL_UNAVAILABLE";
  const safeMessage = typeof error?.code === "string"
    ? error.message
    : "Personal Model 暂时不可用";
  sendJson(res, safeStatus, {
    ok: false,
    code: safeCode,
    error: safeMessage,
  });
}

function sessionPayload(session) {
  return {
    ok: true,
    modelId: session.activeModelId,
    revision: session.revision,
    snapshot: session.snapshot,
  };
}

async function createDevelopmentGrant(modelId) {
  if (!developmentModelRuntime) return null;
  return developmentModelRuntime.createGrant({
    modelId,
    grantTokenService,
  });
}

function setupRequiredError(code, message) {
  const error = new Error(message);
  error.code = code;
  error.status = 409;
  return error;
}

async function personalModelSetupStatus() {
  const cli = resolvePersomeCli();
  const installed = !!cli;
  const managed = managedRuntimeIdentityReady(
    resolve(PERSOME_ROOT, "venv/bin/persome"),
  );
  const existing = !managed && existingRuntimeIdentityReady(
    resolve(PERSOME_ROOT, "venv/bin/persome"),
  );
  let initialized = false;
  let buildStatus = "unavailable";
  let hasUsableModel = false;
  if (DEV_MODE) {
    initialized = true;
    buildStatus = "development";
    hasUsableModel = true;
  } else if (installed) {
    let client;
    try {
      client = await connectPersome();
      const snapshotResult = await client.callTool("get_model_snapshot", {
        redact: true,
        section: "overview",
      });
      const snapshot = parseToolJson(snapshotResult);
      initialized = snapshot?.projection_schema_version === 1
        || snapshot?.schema_version === 1;
      buildStatus = String(snapshot?.build?.status || "not_built");
      const modelStats = snapshot?.model_stats || {};
      hasUsableModel = Boolean(
        snapshot?.root?.id
        || snapshot?.root?.signature
        || (Array.isArray(snapshot?.faces) && snapshot.faces.length > 0)
        || Number(modelStats.roots) > 0
        || Number(modelStats.faces) > 0
        || Number(modelStats.points) > 0,
      );
    } catch {
      initialized = false;
      buildStatus = "unavailable";
      hasUsableModel = false;
    } finally {
      client?.close();
    }
  }
  if (!DEV_MODE && initialized && !ownerProfile) {
    await ensureOwnerProfileForExistingModel({
      allowAccountFallback: existing,
    });
  }
  const profile = ownerProfileStore.publicView();
  let state = "ready";
  if (!profile) state = "profile_required";
  else if (!installed) state = "not_installed";
  else if (!initialized) state = "onboarding_required";
  return Object.freeze({
    ready: DEV_MODE || (!!profile && initialized),
    devMode: DEV_MODE,
    productVersion: PRODUCT_VERSION,
    state,
    profile,
    personalModel: Object.freeze({
      installed,
      initialized,
      buildStatus,
      hasUsableModel,
      version: "0.3.2",
      connection: managed
        ? "product-managed"
        : existing
          ? "existing"
          : installed
            ? "test"
            : "unavailable",
    }),
  });
}

async function serveSetupStatus(req, res) {
  viewerSessionFor(req, res);
  sendJson(res, 200, {
    ok: true,
    ...await personalModelSetupStatus(),
  });
}

async function saveOwnerProfile(req, res) {
  viewerSessionFor(req, res);
  const body = await readJsonBody(req);
  const previousModelId = ownerProfile?.modelId || null;
  ownerProfile = await ownerProfileStore.save({
    displayName: body.displayName,
    handle: body.handle,
    tagline: body.tagline,
    description: body.description,
  });
  if (previousModelId && previousModelId !== ownerProfile.modelId) {
    providerRegistry.unregister(previousModelId);
  }
  registerOwnerProfile(ownerProfile);
  sendJson(res, 200, {
    ok: true,
    ...await personalModelSetupStatus(),
  });
}

async function launchPersonalModelSetup(req, res) {
  viewerSessionFor(req, res);
  if (process.platform !== "darwin") {
    const error = new Error("Personal Model 内测版目前需要 macOS 13 或更新版本");
    error.code = "PLATFORM_UNSUPPORTED";
    error.status = 409;
    throw error;
  }
  if (!existsSync(PERSOME_SETUP_COMMAND)) {
    const error = new Error("安装向导不完整，请重新下载产品");
    error.code = "SETUP_COMMAND_MISSING";
    error.status = 500;
    throw error;
  }
  const child = spawn("/usr/bin/open", [PERSOME_SETUP_COMMAND], {
    detached: true,
    stdio: "ignore",
  });
  child.unref();
  sendJson(res, 202, {
    ok: true,
    launched: true,
    state: (await personalModelSetupStatus()).state,
  });
}

async function ensureActiveModel(session) {
  if (session.activeModelId && session.snapshot) return session;
  const setup = await personalModelSetupStatus();
  if (!setup.ready) {
    throw setupRequiredError(
      setup.state === "profile_required"
        ? "PROFILE_REQUIRED"
        : setup.state === "not_installed"
          ? "RUNTIME_NOT_INSTALLED"
          : "RUNTIME_ONBOARDING_REQUIRED",
      setup.state === "profile_required"
        ? "请先创建你的 Personal Card"
        : setup.state === "not_installed"
          ? "请先安装 Personal Model"
          : "请完成 Personal Model 的本机权限与初始化",
    );
  }
  const modelId = ownerProfile?.modelId || developmentModelRuntime?.ownerModelId || "";
  if (!modelId) {
    throw setupRequiredError("PROFILE_REQUIRED", "请先创建你的 Personal Card");
  }
  return sessionModelService.switchModel({
    sessionId: session.id,
    modelId,
    access: "owner",
  });
}

async function serveModels(req, res) {
  viewerSessionFor(req, res);
  const models = await providerRegistry.listModels();
  sendJson(res, 200, {
    ok: true,
    devMode: DEV_MODE,
    ownerModelId: ownerProfile?.modelId || developmentModelRuntime?.ownerModelId || null,
    models,
  });
}

async function bootstrapActiveModel(req, res) {
  const session = await ensureActiveModel(viewerSessionFor(req, res));
  sendJson(res, 200, sessionPayload(session));
}

async function switchActiveModel(req, res) {
  const session = viewerSessionFor(req, res);
  const body = await readJsonBody(req);
  const modelId = String(body.modelId || "");
  const access = body.access ? String(body.access) : undefined;
  let grantToken = body.grantToken ? String(body.grantToken) : undefined;
  if (!grantToken && DEV_MODE && access === "authorized") {
    grantToken = await createDevelopmentGrant(modelId);
  }
  const switched = await sessionModelService.switchModel({
    sessionId: session.id,
    modelId,
    access,
    grantToken,
  });
  connectorSessionService.revokeForModelSwitch(
    session.id,
    switched.activeModelId,
  );
  evidenceService.revokeCoastFramesForModelSwitch(
    session.id,
    switched.activeModelId,
  );
  const connectorMap = activeConnectorSessions.get(session.id);
  if (connectorMap) {
    for (const [connectorId, connectorSessionId] of connectorMap) {
      try {
        connectorSessionService.resolve(connectorSessionId, {
          viewerSessionId: session.id,
          modelId: switched.activeModelId,
          connectorId,
        });
      } catch {
        connectorMap.delete(connectorId);
      }
    }
  }
  sendJson(res, 200, sessionPayload(switched));
}

function modelContext(req, res, url, body, requiredScope) {
  const session = viewerSessionFor(req, res);
  return createModelRequestContext({
    sessionStore: viewerSessionStore,
    sessionId: session.id,
    body,
    query: url.searchParams,
    requiredScope,
  });
}

async function serveModelCurrentContext(req, res, url) {
  const context = modelContext(req, res, url, undefined, "now:read");
  const provider = providerRegistry.resolve(context.modelId);
  const current = await provider.getCurrentContext(
    context.modelId,
    context.grant,
  );
  sendJson(res, 200, {
    ok: true,
    modelId: context.modelId,
    revision: context.revision,
    current,
  });
}

async function searchActiveModel(req, res, url) {
  const body = await readJsonBody(req);
  const context = modelContext(req, res, url, body, "model:search");
  const query = String(body.query || "").trim().slice(0, 1200);
  const searchOptions = normalizeSearchOptions(body);
  const provider = providerRegistry.resolve(context.modelId);
  const results = await provider.search(
    context.modelId,
    query,
    context.grant,
    searchOptions,
  );
  const sourceRefs = [...new Set(
    results.flatMap((result) => result.sourceRefs || result.evidenceRefs || []),
  )];
  const method = results[0]?.method || "provider-search";
  const degraded = method === "snapshot-keyword-search";
  sendJson(res, 200, {
    ok: true,
    modelId: context.modelId,
    revision: context.revision,
    status: results.length ? "results" : "no_results",
    results,
    contentType: "observed",
    confidence: results.length
      ? Math.max(...results.map((result) => Number(result.confidence) || 0))
      : 0,
    timeRange: {
      since: searchOptions.since || null,
      until: searchOptions.until || null,
    },
    generatedAt: new Date().toISOString(),
    method,
    degraded,
    degradationReason: degraded
      ? "实时语义搜索暂时不可用，当前结果来自已加载模型的关键词匹配。"
      : null,
    sourceRefs,
  });
}

async function askActiveModel(req, res, url) {
  const body = await readJsonBody(req);
  const context = modelContext(req, res, url, body, "model:ask");
  const question = String(body.question || body.text || "").trim().slice(0, 1200);
  if (!question) {
    sendJson(res, 400, {
      ok: false,
      code: "QUESTION_REQUIRED",
      error: "请输入问题",
    });
    return;
  }
  const startedAt = Date.now();
  const searchOptions = normalizeSearchOptions({
    ...body,
    top_k: body.top_k ?? body.topK ?? 5,
  });
  const provider = providerRegistry.resolve(context.modelId);
  let answer;
  if (typeof provider.ask === "function") {
    answer = await provider.ask(
      context.modelId,
      question,
      context.grant,
      {
        ...searchOptions,
        displayName: context.snapshot.model.displayName,
      },
    );
  } else {
    let results = [];
    try {
      results = await provider.search(
        context.modelId,
        question,
        context.grant,
        searchOptions,
      );
    } catch {
      // A search failure becomes a safe refusal instead of a fabricated answer.
    }
    answer = buildGroundedAnswer({
      modelId: context.modelId,
      displayName: context.snapshot.model.displayName,
      results,
    });
  }
  sendJson(res, 200, {
    ok: true,
    ...answer,
    revision: context.revision,
    latencyMs: Date.now() - startedAt,
  });
}

async function correctActiveModel(req, res, url) {
  const body = await readJsonBody(req);
  const context = modelContext(req, res, url, body, "model:correct");
  const correction = typeof body.correction === "string"
    ? body.correction.trim().slice(0, 2400)
    : body.correction && typeof body.correction === "object"
      ? {
          ...body.correction,
          text: String(
            body.correction.text || body.correction.correction || "",
          ).trim().slice(0, 2400),
        }
      : "";
  if (!correction || (typeof correction === "object" && !correction.text)) {
    sendJson(res, 400, {
      ok: false,
      code: "CORRECTION_REQUIRED",
      error: "请输入更正内容",
    });
    return;
  }
  const provider = providerRegistry.resolve(context.modelId);
  const result = await provider.correct(
    context.modelId,
    correction,
    context.grant,
  );
  if (
    result?.status !== "applied" ||
    result?.verification?.status !== "verified" ||
    result?.verification?.oldConclusionDeprioritized !== true
  ) {
    const error = new Error(
      "更正已被接收，但刷新后的 Personal Model 尚未确认旧结论已降级。",
    );
    error.code = "CORRECTION_VERIFICATION_FAILED";
    error.status = 409;
    throw error;
  }
  const refreshed = await sessionModelService.refreshModel({
    sessionId: context.sessionId,
    expectedRevision: context.revision,
  });
  sendJson(res, 200, {
    ok: true,
    modelId: context.modelId,
    revision: refreshed.revision,
    receipt: result.receipt,
    receiptSource: result.receiptSource,
    status: result.status,
    affected: result.affected,
    verification: result.verification,
    result,
  });
}

async function serveModelConnectors(req, res, url) {
  const context = modelContext(req, res, url, undefined, "connectors:read");
  sendJson(res, 200, {
    ok: true,
    modelId: context.modelId,
    revision: context.revision,
    connectors: context.snapshot.connectors || [],
  });
}

async function connectModelConnector(req, res, url, connectorId) {
  const body = await readJsonBody(req);
  const context = modelContext(req, res, url, body, "connectors:connect");
  const provider = providerRegistry.resolve(context.modelId);
  let connector = await provider.connectAgent(
    context.modelId,
    connectorId,
    context.grant,
  );
  const connectorSession = connectorSessionService.create({
    viewerSessionId: context.sessionId,
    modelId: context.modelId,
    connectorId,
    grantId: context.authorization.grantId
      || `owner_${context.modelId}_${context.revision}`,
    scopes: context.scopes,
    expiresAt: context.authorization.expiresAt
      || new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
  });
  if (
    (
      context.modelId === ownerProfile?.modelId
      || developmentModelRuntime?.isOwnerModel(context.modelId)
    )
    && process.env.WHOAMI_PROVIDER_MODE !== "fixture"
    && ["codex", "claude-code"].includes(connectorId)
  ) {
    let target;
    try {
      target = await connectObservableMcpTarget(connectorId, {
        modelId: context.modelId,
        sessionId: connectorSession.sessionId,
        grantId: connectorSession.grantId,
      });
    } catch (error) {
      connectorSessionService.revoke(
        connectorSession.sessionId,
        "connect-failed",
      );
      throw error;
    }
    connector = {
      ...connector,
      status: target.observed ? "connected" : connector.status,
      observed: target.observed,
      installed: target.installed,
      iconUrl: target.iconUrl,
    };
  }
  const connectorMap = activeConnectorSessions.get(context.sessionId)
    || new Map();
  const previousSessionId = connectorMap.get(connectorId);
  if (previousSessionId) {
    connectorSessionService.revoke(previousSessionId, "reconnected");
  }
  connectorMap.set(connectorId, connectorSession.sessionId);
  activeConnectorSessions.set(context.sessionId, connectorMap);
  const receipt = context.snapshot.reports
    ?.find((report) => report.connectorId === connectorId)
    ?.evidenceRefs?.find((reference) =>
      reference.startsWith(`${context.modelId}:`)
    ) || null;
  const event = await connectorEventStore.appendEvent(connectorSession, {
    eventType: "connector/connected",
    tool: "connectAgent",
    receipt,
    summary: `${connectorId} connected to ${context.modelId}`,
  });
  sendJson(res, 200, {
    ok: true,
    modelId: context.modelId,
    revision: context.revision,
    connector: {
      ...connector,
      sessionId: connectorSession.sessionId,
    },
    event,
  });
}

async function disconnectModelConnector(req, res, url, connectorId) {
  const body = await readJsonBody(req);
  const context = modelContext(req, res, url, body, "connectors:connect");
  const connectorMap = activeConnectorSessions.get(context.sessionId);
  const connectorSessionId = connectorMap?.get(connectorId);
  if (!connectorSessionId) {
    const error = new Error("The Connector is not connected in this session.");
    error.code = "CONNECTOR_SESSION_NOT_FOUND";
    error.status = 404;
    throw error;
  }
  const connectorSession = connectorSessionService.resolve(
    connectorSessionId,
    {
      viewerSessionId: context.sessionId,
      modelId: context.modelId,
      connectorId,
      requiredScope: "connectors:connect",
    },
  );
  const event = await connectorEventStore.appendEvent(connectorSession, {
    eventType: "connector/disconnected",
    tool: "disconnectAgent",
    summary: `${connectorId} disconnected from ${context.modelId}`,
  });
  connectorSessionService.revoke(connectorSessionId, "disconnected");
  connectorMap.delete(connectorId);
  if (connectorMap.size === 0) {
    activeConnectorSessions.delete(context.sessionId);
  }
  sendJson(res, 200, {
    ok: true,
    modelId: context.modelId,
    revision: context.revision,
    connector: {
      connectorId,
      status: "available",
      sessionId: connectorSessionId,
    },
    event,
  });
}

async function serveModelReports(req, res, url) {
  const context = modelContext(req, res, url, undefined, "reports:read");
  const provider = providerRegistry.resolve(context.modelId);
  const snapshotReports = await provider.listAgentReports(
    context.modelId,
    context.grant,
  );
  const connectorMap = activeConnectorSessions.get(context.sessionId);
  const dynamicReports = [];
  const events = [];
  if (connectorMap) {
    for (const [connectorId, connectorSessionId] of connectorMap) {
      try {
        const reports = await reportService.listReports({
          sessionId: connectorSessionId,
          viewerSessionId: context.sessionId,
          modelId: context.modelId,
          connectorId,
        });
        dynamicReports.push(...reports);
        events.push(...await connectorEventStore.readEvents({
          modelId: context.modelId,
          connectorId,
          sessionId: connectorSessionId,
        }));
      } catch {
        connectorMap.delete(connectorId);
      }
    }
  }
  sendJson(res, 200, {
    ok: true,
    modelId: context.modelId,
    revision: context.revision,
    reports: [...snapshotReports, ...dynamicReports],
    events,
  });
}

async function serveModelEvidence(req, res, url, pathReference) {
  const context = modelContext(req, res, url, undefined, "evidence:read");
  const reference = String(
    pathReference || url.searchParams.get("reference") || "",
  );
  const connectorSessionId = String(
    url.searchParams.get("connectorSessionId") || "",
  );
  let evidence;
  if (connectorSessionId) {
    evidence = await evidenceService.getEvidence({
      viewerSessionId: context.sessionId,
      activeModelId: context.modelId,
      connectorSessionId,
      reference,
    });
  } else {
    const provider = providerRegistry.resolve(context.modelId);
    evidence = await provider.getEvidence(
      context.modelId,
      reference,
      context.grant,
    );
  }
  sendJson(res, 200, {
    ok: true,
    modelId: context.modelId,
    revision: context.revision,
    evidence,
  });
}

async function serveModelRewindFrames(req, res, url) {
  const context = modelContext(req, res, url, undefined, "rewind:read");
  requireScope(context.authorization, "evidence:read");
  const dayId = String(url.searchParams.get("day") || "");
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(dayId)
    || !context.snapshot.time?.days?.some((day) => day.id === dayId)
  ) {
    sendJson(res, 404, {
      ok: false,
      code: "REWIND_DAY_NOT_FOUND",
      error: "这一天不在当前 Personal Model 的 Rewind 中",
    });
    return;
  }

  const frames = await coastFramesForDay(dayId);
  const responseFrames = frames.map((frame) => {
    const frameId = String(frame.id);
    evidenceService.allowCoastFrame({
      viewerSessionId: context.sessionId,
      modelId: context.modelId,
      frameId,
    });
    return {
      reference: `${context.modelId}:coast:${frameId}`,
      time: frame.time,
      app: frame.app,
      title: frame.title,
      duration: frame.duration,
      color: frame.color,
      timestamp: frame.timestamp,
    };
  });
  sendJson(res, 200, {
    ok: true,
    modelId: context.modelId,
    revision: context.revision,
    dayId,
    source: responseFrames.length
      ? `Coast · ${responseFrames.length} 个代表画面`
      : "Coast · 当天没有可用画面",
    frames: responseFrames,
  });
}

async function serveModelRewindFrame(req, res, url) {
  const context = modelContext(req, res, url, undefined, "evidence:read");
  requireScope(context.authorization, "rewind:read");
  const reference = String(url.searchParams.get("reference") || "");
  const evidence = await evidenceService.getCoastFrame({
    viewerSessionId: context.sessionId,
    activeModelId: context.modelId,
    reference,
  });
  const imagePath = secureCoastImagePath(evidence.content?.imagePath);
  if (!imagePath) {
    sendJson(res, 404, {
      ok: false,
      code: "COAST_FRAME_NOT_FOUND",
      error: "这个画面已不可用",
    });
    return;
  }
  const image = await readFile(imagePath);
  res.writeHead(200, {
    "Content-Type": "image/png",
    "Content-Length": image.length,
    "Cache-Control": "private, max-age=300",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    ...(res.whoamiSetCookie ? { "Set-Cookie": res.whoamiSetCookie } : {}),
  });
  res.end(image);
}

async function bootstrapPersome(res) {
  const bootstrapModelId = ownerProfile?.modelId
    || developmentModelRuntime?.ownerModelId
    || "local-owner";
  const client = await connectPersome();
  try {
    const since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const safeTool = (name, args) => client.callTool(name, args).catch(() => null);
    const [memoriesResult, behaviorResult, activityResult, currentResult] = await Promise.all([
      client.callTool("list_memories", {}),
      client.callTool("behavior_patterns", {}),
      safeTool("recent_activity", { since, limit: 120, prefix_filter: ["event"] }),
      safeTool("current_context", { timeline_limit: 10, headline_limit: 4, fulltext_limit: 0 }),
    ]);
    const memories = parseToolJson(memoriesResult);
    const behavior = parseToolJson(behaviorResult);
    const activity = parseToolJson(activityResult);
    const current = parseToolJson(currentResult);
    let live = await attachCoastFrames(
      buildLivePayload(activity, current),
      bootstrapModelId,
    );
    if (Array.isArray(live.days) && live.days.length) {
      await mkdir(dirname(LIVE_CACHE_PATH), { recursive: true });
      await writeFile(LIVE_CACHE_PATH, JSON.stringify(live), "utf8").catch(() => {});
    } else {
      const cachedLive = await readFile(LIVE_CACHE_PATH, "utf8")
        .then((text) => JSON.parse(text))
        .catch(() => null);
      if (cachedLive && Array.isArray(cachedLive.days) && cachedLive.days.length) {
        for (const day of cachedLive.days) {
          for (const frame of day.coastFrames || []) {
            if (frame?.id != null) {
              const allowedFrameIds = allowedCoastFrameIdsByModel.get(bootstrapModelId) || new Set();
              allowedFrameIds.add(String(frame.id));
              allowedCoastFrameIdsByModel.set(bootstrapModelId, allowedFrameIds);
            }
          }
        }
        live = {
          ...cachedLive,
          generatedAt: live.generatedAt,
          clockLabel: live.clockLabel,
          monthLabel: live.monthLabel,
          yearLabel: live.yearLabel,
          proactiveLabel: live.proactiveLabel,
          futureEvents: live.futureEvents,
          nowItems: cachedLive.nowItems,
          cacheStatus: "最近一次完整记录",
        };
      }
    }
    const files = Array.isArray(memories.files) ? memories.files : [];
    const faces = (Array.isArray(behavior.faces) ? behavior.faces : []).slice(0, 6).map((face) => ({
      text: cleanModelText(face.signature, 260),
      observations: face.observations ?? null,
      confidence: face.confidence ?? null,
    }));
    const updatedAt = files
      .map((file) => file.updated)
      .filter(Boolean)
      .sort()
      .at(-1) || null;

    sendJson(res, 200, {
      ok: true,
      memoryCount: Number.isFinite(memories.count) ? memories.count : files.length,
      root: rootSummary(behavior?.root?.signature),
      faces,
      updatedAt,
      live,
      source: "Persome MCP · localhost",
    });
  } finally {
    client.close();
  }
}

function modelEvidenceRef(modelId, kind, value) {
  const safe = String(value || "memory")
    .replace(/[^A-Za-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 72) || "memory";
  return `${modelId}:${kind}:${safe}`;
}

function runtimeReferenceFromModelEvidence(modelId, reference) {
  const prefix = `${modelId}:`;
  if (!String(reference).startsWith(prefix)) return "";
  const partitioned = String(reference).slice(prefix.length);
  const separator = partitioned.indexOf(":");
  return separator >= 0 ? partitioned.slice(separator + 1) : "";
}

function modelBoundRuntimeReference(modelId, source) {
  const reference = String(source?.reference || source?.id || "").trim();
  const kind = String(source?.kind || "source")
    .replace(/[^A-Za-z0-9_-]+/g, "-") || "source";
  return reference ? `${modelId}:${kind}:${reference}` : null;
}

async function resolveLocalEvidence(modelId, reference) {
  const runtimeReference = runtimeReferenceFromModelEvidence(
    modelId,
    reference,
  );
  if (!runtimeReference) return null;
  const client = await connectPersome();
  try {
    const result = parseToolJson(
      await client.callTool("resolve_evidence", {
        reference: runtimeReference,
      }),
    );
    const kind = String(result.kind || "unknown");
    const status = String(result.status || "missing");
    const summary = String(result.summary || "").trim();
    const timestamp = String(
      result.metadata?.occurred_at || result.timestamp || "",
    ).trim();
    const validTimestamp = Number.isFinite(Date.parse(timestamp));
    const normalizedTimestamp = validTimestamp
      ? new Date(timestamp).toISOString()
      : null;
    if (
      kind === "unknown" ||
      status === "missing" ||
      !summary
    ) {
      return null;
    }

    const isActivityMemory = kind === "memory"
      && /^event-/u.test(String(result.path || ""));
    const rawKind = isActivityMemory
      ? "persome-activity"
      : kind === "memory"
        ? "persome-memory"
      : ["activity", "capture"].includes(kind) &&
          status !== "metadata_only"
        ? "persome-activity"
        : null;
    if (rawKind && !validTimestamp) return null;
    const sourceType = rawKind || "derived-summary";
    const lineage = (Array.isArray(result.sources) ? result.sources : [])
      .map((source) => ({
        relation: String(source.relation || "lineage"),
        kind: String(source.kind || "source"),
        reference: modelBoundRuntimeReference(modelId, source),
        label: String(source.label || ""),
        timestamp:
          typeof source.timestamp === "string" ? source.timestamp : null,
      }))
      .filter(({ reference: sourceReference }) => sourceReference);
    const history = (Array.isArray(result.history) ? result.history : [])
      .map((entry) => ({
        relation: String(entry.relation || "history"),
        kind: String(entry.kind || "source"),
        reference: modelBoundRuntimeReference(modelId, entry),
        label: String(entry.label || ""),
        timestamp:
          typeof entry.timestamp === "string" ? entry.timestamp : null,
      }))
      .filter(({ reference: historyReference }) => historyReference);
    return {
      modelId,
      reference,
      source: {
        type: sourceType,
        originalTime: normalizedTimestamp,
        application: String(
          result.metadata?.app_name ||
          result.metadata?.source_kind ||
          "Persome",
        ),
        title: String(result.label || kind),
        ...(result.id ? { recordId: String(result.id) } : {}),
      },
      supports: [
        {
          claim: summary,
          relationship: rawKind ? "direct" : "indirect",
        },
      ],
      availability: { status: "available" },
      content: {
        runtimeReceipt: result.canonical_reference || runtimeReference,
        kind,
        status,
        summary,
        path: result.path || null,
        metadata:
          result.metadata && typeof result.metadata === "object"
            ? result.metadata
            : {},
        lineage,
        history,
      },
      ...(result.canonical_reference
        ? { receipt: String(result.canonical_reference) }
        : {}),
      ...(normalizedTimestamp ? { capturedAt: normalizedTimestamp } : {}),
    };
  } finally {
    client.close();
  }
}

async function loadLocalOwnerSnapshot(profile) {
  const client = await connectPersome();
  try {
    const modelId = profile.modelId;
    const since = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000).toISOString();
    const safeTool = (name, args) => client.callTool(name, args).catch(() => null);
    const [
      memoriesResult,
      behaviorResult,
      modelFacesResult,
      activityResult,
      currentResult,
      targets,
    ] =
      await Promise.all([
        safeTool("list_memories", {}),
        safeTool("behavior_patterns", {}),
        safeTool("get_model_snapshot", {
          redact: true,
          section: "faces",
          include_evidence_refs: true,
          limit: 100,
        }),
        safeTool("recent_activity", {
          since,
          limit: 120,
          prefix_filter: ["event"],
        }),
        safeTool("current_context", {
          timeline_limit: 10,
          headline_limit: 4,
          fulltext_limit: 0,
        }),
        Promise.all([
          mcpTargetStatus("claude-code"),
          mcpTargetStatus("codex"),
        ]),
      ]);
    const memories = parseToolJson(memoriesResult);
    const behavior = parseToolJson(behaviorResult);
    const modelFaces = parseToolJson(modelFacesResult);
    const activity = parseToolJson(activityResult);
    const current = parseToolJson(currentResult);
    const live = buildLivePayload(activity, current);
    const files = Array.isArray(memories.files) ? memories.files : [];
    const projectedFaces = Array.isArray(modelFaces?.items)
      ? modelFaces.items.filter((face) =>
          typeof face?.id === "string" && face.id.trim()
          && typeof face?.signature === "string" && face.signature.trim()
          && face.status !== "inactive"
        )
      : [];
    const faceCandidates = projectedFaces.length
      ? projectedFaces
      : (Array.isArray(behavior.faces) ? behavior.faces : []);
    const faces = faceCandidates
      .toSorted((a, b) =>
        (Number(b?.observations) || 0) - (Number(a?.observations) || 0)
      )
      .slice(0, 6)
      .map((face, index) => ({
        id: `face_${modelId}_${String(index + 1).padStart(2, "0")}`,
        text: cleanModelText(face.signature || face.text, 260),
        observations: Math.max(0, Math.round(Number(face.observations) || 0)),
        confidence: Math.min(1, Math.max(0, Number(face.confidence) || 0)),
        ...(typeof face.id === "string" && face.id.trim()
          ? {
              evidenceRefs: [modelEvidenceRef(modelId, "face", face.id)],
            }
          : {}),
      }))
      .filter((face) => face.text);
    const days = (Array.isArray(live.days) ? live.days : [])
      .slice(0, 14)
      .map((day) => ({
        id: day.key,
        title: day.title,
        portrait: day.portrait || day.narr || "",
        letter: Array.isArray(day.selfReading?.letter)
          ? day.selfReading.letter.join("\n")
          : String(day.letter || ""),
        events: (Array.isArray(day.events) ? day.events : []).map(
          (event, index) => {
            const sourceId = String(event.sourceId || "").trim();
            const evidenceRef = sourceId && !sourceId.startsWith("live-")
              ? modelEvidenceRef(modelId, "event", sourceId)
              : null;
            return {
              id: `${modelId}-live-${day.key}-${String(index + 1).padStart(2, "0")}`,
              time: event.t || "—",
              title: event.title || "Personal Model",
              detail: event.detail || event.io || "",
              app: String(event.io || "").split(" · ")[0] || "Personal Model",
              ...(evidenceRef ? { evidenceRef } : {}),
            };
          },
        ),
      }))
      .filter((day) => day.id && day.events.length);
    const kindMap = {
      past: "past",
      present: "present",
      future: "future",
      "过去": "past",
      "现在": "present",
      "未来": "future",
    };
    const nowGeneratedAt = Number.isFinite(Date.parse(live.generatedAt))
      ? new Date(live.generatedAt).toISOString()
      : new Date().toISOString();
    const nowRangeStart = new Date(
      Date.parse(nowGeneratedAt) - 7 * 24 * 60 * 60 * 1000,
    ).toISOString();
    // An event without an evidenceRef would otherwise put undefined into
    // sourceRefs, and the Card contract requires every entry to be a string of
    // at least MINIMUM_SOURCE_REF_LENGTH. Drop anything the contract would
    // reject rather than fail the whole Snapshot over one reference, and
    // filter before slicing so a missing ref cannot displace a usable one.
    const nowSourceRefs = [...new Set(
      days.flatMap((day) => day.events.map((event) => event.evidenceRef)),
    )]
      .filter((ref) =>
        typeof ref === "string" && ref.length >= MINIMUM_SOURCE_REF_LENGTH
      )
      .slice(0, 6);
    const nowItems = (Array.isArray(live.nowItems) ? live.nowItems : [])
      .filter((item) => item?.title)
      .slice(0, 6)
      .map((item, index) => {
        const kind = kindMap[item.kind] || "present";
        return {
          id: String(item.id || `${modelId}-now-${index + 1}`),
          kind,
          title: String(item.title),
          why: String(item.why || ""),
          when: String(item.t || item.when || "现在"),
          ...(item.day ? { dayId: String(item.day) } : {}),
          ...(item.app ? { app: String(item.app) } : {}),
          metadata: {
            provenance: kind === "future" ? "generated" : "inferred",
            ...(nowSourceRefs.length ? { sourceRefs: nowSourceRefs } : {}),
            timeRange: { start: nowRangeStart, end: nowGeneratedAt },
            generatedAt: nowGeneratedAt,
            method: kind === "future"
              ? "continuation-suggestion from Persome recent_activity / current_context"
              : "Persome recent_activity / current_context",
          },
        };
      });
    const updatedValue = files
      .map((file) => file.updated)
      .filter((value) => Number.isFinite(Date.parse(value)))
      .sort()
      .at(-1);
    const updatedAt = updatedValue
      ? new Date(updatedValue).toISOString()
      : new Date().toISOString();
    const latestDay = days[0];
    const weeklyLetter = String(latestDay?.letter || "")
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean)
      .slice(0, 4);
    const now = new Date();
    const monthYear = `${new Intl.DateTimeFormat("en-US", {
      month: "long",
    }).format(now).toUpperCase()} / ${now.getFullYear()}`;

    return {
      schemaVersion: "1.0.0",
      model: {
        id: modelId,
        displayName: profile.displayName,
        handle: `@${profile.handle}`,
        memberNumber: profile.memberNumber,
        sinceYear: profile.sinceYear,
        status: "online",
      },
      authorization: {
        viewerMode: "owner",
        scopes: [...OWNER_SCOPES],
      },
      card: {
        monthYear,
        tagline: profile.tagline,
        publicUrl: profile.publicUrl,
        material: profile.material,
        glyph: [...profile.glyph],
      },
      personalModel: {
        memoryCount: Number.isFinite(memories.count)
          ? Math.max(0, Math.round(memories.count))
          : files.length,
        root: rootSummary(behavior?.root?.signature),
        faces,
        updatedAt,
      },
      now: { items: nowItems },
      time: { days },
      identity: {
        description: profile.description,
        dailyLine: latestDay?.portrait || live.observation || "你的 Personal Model 正在形成。",
        weeklyLetter,
      },
      connectors: targets.map((target) => ({
        id: target.id,
        name: target.name,
        product: target.name,
        status: target.observed
          ? "connected"
          : target.installed
            ? "available"
            : "missing",
        iconUrl: target.iconUrl,
      })),
      reports: [],
    };
  } finally {
    client.close();
  }
}

async function writeLocalCorrection(correction) {
  const client = await connectPersome();
  try {
    const result = await client.callTool("correct_memory", { correction });
    return parseToolJson(result);
  } finally {
    client.close();
  }
}

function readableChinese(value, max = 220) {
  const text = cleanModelText(value, max);
  const chinese = (text.match(/[\u3400-\u9fff]/g) || []).length;
  if (!text || chinese < 6) return "";
  if (/https?:\/\/|\/Users\/|\.json\b|\.md\b|function\b|const\b|mcp_servers/i.test(text)) return "";
  return text;
}

function mirrorOpening(text) {
  const core = text
    .replace(/^(?:我最近)?(?:有点)?(?:觉得|发现|好像|其实|一直)?(?:我)?(?:有点)?/, "")
    .replace(/^想/, "")
    .replace(/[。！？!?]+$/, "")
    .trim();
  if (/累|疲惫|撑不住|没力气/.test(text)) return "你现在不是在汇报状态，只是在确认：自己已经撑了一段时间。";
  if (/焦虑|担心|害怕|不安/.test(text)) return `你在说的也许不只是担心，而是有一件重要的事还没有获得确定感${core ? "——" + core : ""}。`;
  if (/开心|喜欢|兴奋|期待/.test(text)) return `这一刻值得被留下：${core || text.replace(/^我/, "你")}。`;
  if (/想|希望|方向|产品|选择/.test(text)) return `这不像一个待办，更像你在替自己确认方向：${core || text.replace(/^我/, "你")}。`;
  return `我先不解释。你此刻想让自己看见的是：${text.replace(/^我/, "你")}。`;
}

async function reflectPersome(req, res) {
  const body = await readJsonBody(req);
  const text = cleanModelText(String(body.text || "").trim(), 420);
  if (!text) {
    sendJson(res, 400, { ok: false, error: "说一点你此刻正在想的事" });
    return;
  }
  const client = await connectPersome();
  try {
    const [searchResult, behaviorResult] = await Promise.all([
      client.callTool("search", {
        query: text,
        top_k: 4,
        breadth: 0.45,
        include_bodies: true,
      }).catch(() => null),
      client.callTool("behavior_patterns", {}).catch(() => null),
    ]);
    const search = parseToolJson(searchResult);
    const behavior = parseToolJson(behaviorResult);
    const hits = (Array.isArray(search.hits) ? search.hits : search.results || []);
    const evidenceHit = hits.find((hit) => readableChinese(hit.content || hit.text || hit.summary, 230));
    const evidence = evidenceHit
      ? readableChinese(evidenceHit.content || evidenceHit.text || evidenceHit.summary, 230)
      : "";
    const faces = Array.isArray(behavior.faces) ? behavior.faces : [];
    const face = faces
      .map((item) => readableChinese(item.signature || item.text, 190))
      .find(Boolean) || readableChinese(rootSummary(behavior?.root?.signature), 190);
    const pieces = [
      mirrorOpening(text),
      evidence ? `过去的记忆里，有一段和它靠得很近：${evidence}` : "",
      face ? `再往后看，Personal Model 里反复出现过这样的你：${face}` : "",
      evidence || face
        ? "它们不一定解释现在，只是让这一刻不再是一句说完就消失的话。"
        : "我先不解释，也不把它变成待办。等更多经历靠近，它会慢慢有上下文。",
    ].filter(Boolean);
    const day = evidenceHit ? dateKey(evidenceHit.path || evidenceHit.timestamp) : "";
    sendJson(res, 200, {
      ok: true,
      answer: pieces.join("\n\n"),
      day: day || null,
      tools: ["search", "behavior_patterns"],
    });
  } finally {
    client.close();
  }
}

async function correctPersome(req, res) {
  const body = await readJsonBody(req);
  const correction = String(body.correction || "").trim().slice(0, 2400);
  if (!correction) {
    sendJson(res, 400, { ok: false, error: "请输入更正内容" });
    return;
  }
  const client = await connectPersome();
  try {
    await client.callTool("correct_memory", { correction });
    sendJson(res, 200, { ok: true });
  } finally {
    client.close();
  }
}

async function serveStatic(req, res, url) {
  viewerSessionFor(req, res);
  const requested = url.pathname === "/" ? CARD_FILE : decodeURIComponent(url.pathname.slice(1));
  const filePath = resolve(CARD_ROOT, requested);
  if (filePath !== CARD_ROOT && !filePath.startsWith(`${CARD_ROOT}${sep}`)) {
    res.writeHead(403);
    res.end("Forbidden");
    return;
  }
  try {
    const file = await readFile(filePath);
    res.writeHead(200, {
      "Content-Type": mimeTypes[extname(filePath)] || "application/octet-stream",
      ...(res.whoamiSetCookie ? { "Set-Cookie": res.whoamiSetCookie } : {}),
      "X-Frame-Options": "DENY",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
      "Cache-Control": extname(filePath) === ".html" ? "no-store" : "public, max-age=300",
    });
    if (req.method === "HEAD") res.end();
    else res.end(file);
  } catch {
    res.writeHead(404);
    res.end("Not found");
  }
}

async function serveCoastFrame(res, url, modelId = ownerProfile?.modelId || "local-owner") {
  const id = String(url.searchParams.get("id") || "");
  if (!/^\d{1,12}$/.test(id)) {
    sendJson(res, 400, { ok: false, error: "无效的 Coast frame" });
    return;
  }
  if (!allowedCoastFrameIdsByModel.get(modelId)?.has(id)) {
    sendJson(res, 404, { ok: false, error: "这个画面不在当前安全回放中" });
    return;
  }
  const { stdout } = await runCoast(["query", "image", "--id", id, "--crop"], 15000);
  const filePath = stdout.split(/\r?\n/).map((line) => line.trim()).find(Boolean) || "";
  if (!filePath.startsWith("/tmp/coast-cli/") || !filePath.endsWith(".png")) {
    throw new Error("Coast 没有返回可用画面");
  }
  const image = await readFile(filePath);
  res.writeHead(200, {
    "Content-Type": "image/png",
    "Content-Length": image.length,
    "Cache-Control": "private, max-age=300",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
  });
  res.end(image);
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url || "/", `http://${CARD_HOST}:${CARD_PORT}`);
  try {
    if (url.pathname.startsWith("/api/")) {
      if (!allowedRequest(req)) {
        sendJson(res, 403, {
          ok: false,
          code: "ORIGIN_FORBIDDEN",
          error: "只允许这张本地卡片访问 Personal Model",
        });
        return;
      }
      if (req.method === "GET" && url.pathname === "/api/app/health") {
        sendJson(res, 200, {
          ok: true,
          productVersion: PRODUCT_VERSION,
          devMode: DEV_MODE,
        });
        return;
      }
      if (req.method === "GET" && url.pathname === "/api/setup/status") {
        await serveSetupStatus(req, res);
        return;
      }
      if (req.method === "POST" && url.pathname === "/api/setup/profile") {
        await saveOwnerProfile(req, res);
        return;
      }
      if (req.method === "POST" && url.pathname === "/api/setup/personal-model") {
        await launchPersonalModelSetup(req, res);
        return;
      }
      if (req.method === "GET" && url.pathname === "/api/models") {
        await serveModels(req, res);
        return;
      }
      if (req.method === "GET" && url.pathname === "/api/model/bootstrap") {
        await bootstrapActiveModel(req, res);
        return;
      }
      if (req.method === "POST" && url.pathname === "/api/session/model") {
        await switchActiveModel(req, res);
        return;
      }
      if (req.method === "GET" && url.pathname === "/api/model/context") {
        await serveModelCurrentContext(req, res, url);
        return;
      }
      if (req.method === "POST" && url.pathname === "/api/model/search") {
        await searchActiveModel(req, res, url);
        return;
      }
      if (req.method === "POST" && url.pathname === "/api/model/ask") {
        await askActiveModel(req, res, url);
        return;
      }
      if (req.method === "POST" && url.pathname === "/api/model/correct") {
        await correctActiveModel(req, res, url);
        return;
      }
      if (req.method === "GET" && url.pathname === "/api/model/connectors") {
        await serveModelConnectors(req, res, url);
        return;
      }
      const connectorMatch = url.pathname.match(
        /^\/api\/model\/connectors\/([A-Za-z0-9_-]+)\/connect$/,
      );
      if (req.method === "POST" && connectorMatch) {
        await connectModelConnector(req, res, url, connectorMatch[1]);
        return;
      }
      const connectorDisconnectMatch = url.pathname.match(
        /^\/api\/model\/connectors\/([A-Za-z0-9_-]+)\/disconnect$/,
      );
      if (req.method === "POST" && connectorDisconnectMatch) {
        await disconnectModelConnector(
          req,
          res,
          url,
          connectorDisconnectMatch[1],
        );
        return;
      }
      if (req.method === "GET" && url.pathname === "/api/model/reports") {
        await serveModelReports(req, res, url);
        return;
      }
      if (req.method === "GET" && url.pathname === "/api/model/rewind/frames") {
        await serveModelRewindFrames(req, res, url);
        return;
      }
      if (req.method === "GET" && url.pathname === "/api/model/rewind/frame") {
        await serveModelRewindFrame(req, res, url);
        return;
      }
      if (req.method === "GET" && url.pathname === "/api/model/evidence") {
        await serveModelEvidence(req, res, url);
        return;
      }
      const evidenceMatch = url.pathname.match(/^\/api\/model\/evidence\/(.+)$/);
      if (req.method === "GET" && evidenceMatch) {
        await serveModelEvidence(
          req,
          res,
          url,
          decodeURIComponent(evidenceMatch[1]),
        );
        return;
      }
      if (url.pathname.startsWith("/api/persome/")) {
        sendJson(res, 410, {
          ok: false,
          code: "LEGACY_API_DISABLED",
          error: "请使用会话绑定的 Personal Model API",
        });
        return;
      }
      sendJson(res, 404, {
        ok: false,
        code: "API_NOT_FOUND",
        error: "Not found",
      });
      return;
    }
    if (req.method !== "GET" && req.method !== "HEAD") {
      res.writeHead(405);
      res.end("Method not allowed");
      return;
    }
    await serveStatic(req, res, url);
  } catch (error) {
    sendError(res, 503, error);
  }
});

server.listen(CARD_PORT, CARD_HOST, () => {
  console.log(`Who Am I · Persome Live`);
  console.log(`http://${CARD_HOST}:${CARD_PORT}/`);
});
