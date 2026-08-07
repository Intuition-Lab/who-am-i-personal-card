import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdir, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { chromium } from "playwright-core";

const projectRoot = fileURLToPath(new URL("../../", import.meta.url));
const chromePath = process.env.CHROME_PATH
  || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const port = Number(process.env.WHOAMI_NO_DEMO_TEST_PORT || 20772);
const baseUrl = `http://127.0.0.1:${port}`;

const forbidden = [
  ["Ceci", "lia"].join(""),
  ["@ceci", "lia"].join(""),
  ["lin", "-demo"].join(""),
  ["Lin", " · @lin"].join(""),
  ["z", "sy"].join(""),
  ["Personal Card 的", "上一版"].join(""),
  ["继续 ", "Personal Card"].join(""),
  ["Designing quieter ", "tools for cities"].join(""),
  ["Product person building ", "Who Am I"].join(""),
  ["Urban interaction ", "designer"].join(""),
  ["pm.app/", "cecilia"].join(""),
  ["pm.app/", "lin"].join(""),
];

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

function assertNoDemo(label, value) {
  const text = typeof value === "string" ? value : JSON.stringify(value);
  const leaked = forbidden.filter((token) => text.includes(token));
  invariant(
    leaked.length === 0,
    `${label} leaked production demo identity/content: ${leaked.join(", ")}`,
  );
}

async function waitForServer(child) {
  for (let attempt = 0; attempt < 140; attempt += 1) {
    if (child.exitCode !== null) {
      throw new Error(`Production server exited with ${child.exitCode}`);
    }
    try {
      const response = await fetch(baseUrl, { method: "HEAD" });
      if (response.ok) return;
    } catch {
      // Startup is asynchronous.
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error("Timed out waiting for the production server.");
}

async function stopServer(child) {
  if (child.exitCode === null) child.kill("SIGTERM");
  if (child.exitCode === null) await once(child, "exit");
}

const tempRoot = await mkdtemp(path.join(tmpdir(), "whoami-fresh-home-no-demo-"));
const freshHome = path.join(tempRoot, "home");
const cardDataDir = path.join(tempRoot, "card-data");
const persomeRoot = path.join(freshHome, ".persome");
await mkdir(freshHome, { recursive: true, mode: 0o700 });

const server = spawn(process.execPath, ["persome-card-server.mjs"], {
  cwd: projectRoot,
  env: {
    ...process.env,
    HOME: freshHome,
    NODE_ENV: "production",
    WHOAMI_DEV_MODE: "0",
    WHOAMI_TEST_MODE: "0",
    WHOAMI_PROVIDER_MODE: "fixture",
    WHOAMI_CARD_PORT: String(port),
    WHOAMI_CARD_DATA_DIR: cardDataDir,
    PERSOME_ROOT: persomeRoot,
    PERSOME_CLI: path.join(tempRoot, "must-not-be-used", "persome"),
    PERSOME_MCP_URL: "http://127.0.0.1:1/mcp",
    PATH: path.dirname(process.execPath),
  },
  stdio: ["ignore", "ignore", "pipe"],
});

let browser;
try {
  await waitForServer(server);
  browser = await chromium.launch({ executablePath: chromePath, headless: true });
  const context = await browser.newContext({
    viewport: { width: 1440, height: 1000 },
    deviceScaleFactor: 1,
  });
  const page = await context.newPage();
  const consoleErrors = [];
  page.on("console", (message) => {
    if (
      message.type() === "error"
      && !message.text().includes("{{")
      && !message.text().startsWith("Failed to load resource:")
    ) {
      consoleErrors.push(message.text());
    }
  });
  page.on("pageerror", (error) => consoleErrors.push(error.message));

  await page.goto(`${baseUrl}/?dev=1&model=lin-demo`, {
    waitUntil: "domcontentloaded",
  });
  await page.getByText("先让这张卡成为你的。", { exact: true }).waitFor();
  assertNoDemo("fresh HOME page", await page.locator("body").innerText());

  const initialApi = await page.evaluate(async () => {
    const read = async (url, options) => {
      const response = await fetch(url, options);
      return { status: response.status, body: await response.json() };
    };
    return {
      setup: await read("/api/setup/status"),
      models: await read("/api/models"),
      bootstrap: await read("/api/model/bootstrap"),
    };
  });
  invariant(initialApi.setup.body.ready === false, "Fresh HOME was marked ready.");
  invariant(initialApi.models.body.devMode === false, "Fresh HOME enabled dev mode.");
  invariant(initialApi.models.body.models.length === 0, "Fresh HOME registered a model.");
  invariant(initialApi.bootstrap.status === 409, "Unavailable model Snapshot was returned.");
  assertNoDemo("fresh HOME API responses", initialApi);

  await page.locator("[data-setup-name]").fill("Fresh Owner");
  await page.locator("[data-setup-handle]").fill("@fresh-owner");
  await page.locator("[data-setup-tagline]").fill("A blank local card");
  await page.locator("[data-setup-description]").fill("Waiting for this Mac's model");
  await page.getByText("创建我的 Personal Card", { exact: true }).click();
  await page.getByText("卡片身份已保存", { exact: true }).waitFor();

  const unavailableApi = await page.evaluate(async () => {
    const response = await fetch("/api/model/bootstrap");
    return { status: response.status, body: await response.json() };
  });
  invariant(
    unavailableApi.status === 409,
    "A profile without a usable Personal Model received a Snapshot.",
  );
  assertNoDemo("unavailable Snapshot response", unavailableApi);
  assertNoDemo("unavailable Snapshot page", await page.locator("body").innerText());
  invariant(consoleErrors.length === 0, consoleErrors.join("\n"));
  console.log("Fresh HOME/unavailable Snapshot rendered no demo identity or Card copy.");
} finally {
  if (browser) await browser.close();
  await stopServer(server);
  await rm(tempRoot, { recursive: true, force: true });
}
