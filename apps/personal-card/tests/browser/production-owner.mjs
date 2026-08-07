import { spawn } from "node:child_process";
import { once } from "node:events";
import {
  chmod,
  mkdir,
  mkdtemp,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { chromium } from "playwright-core";

const projectRoot = fileURLToPath(new URL("../../", import.meta.url));
const fakePersome = fileURLToPath(
  new URL("../fixtures/fake-persome-cli.mjs", import.meta.url),
);
const chromePath = process.env.CHROME_PATH
  || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const port = Number(process.env.WHOAMI_OWNER_TEST_PORT || 19772);
const baseUrl = `http://127.0.0.1:${port}`;
const outputArgIndex = process.argv.indexOf("--output");
const outputDir = path.resolve(
  projectRoot,
  outputArgIndex >= 0 && process.argv[outputArgIndex + 1]
    ? process.argv[outputArgIndex + 1]
    : "tests/visual/current",
);

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

async function waitForServer(child) {
  for (let attempt = 0; attempt < 120; attempt += 1) {
    if (child.exitCode !== null) {
      throw new Error(`Personal Card server exited with ${child.exitCode}`);
    }
    try {
      const response = await fetch(baseUrl, { method: "HEAD" });
      if (response.ok) return;
    } catch {
      // Startup is asynchronous.
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error("Timed out waiting for the production Personal Card server.");
}

function startServer(cardDataDir, persomeRoot) {
  return spawn(process.execPath, ["persome-card-server.mjs"], {
    cwd: projectRoot,
    env: {
      ...process.env,
      NODE_ENV: "production",
      WHOAMI_DEV_MODE: "0",
      WHOAMI_TEST_MODE: "1",
      WHOAMI_PROVIDER_MODE: "fixture",
      WHOAMI_CARD_PORT: String(port),
      WHOAMI_CARD_DATA_DIR: cardDataDir,
      PERSOME_ROOT: persomeRoot,
      PERSOME_CLI: fakePersome,
      PERSOME_MCP_URL: "http://127.0.0.1:1/mcp",
    },
    stdio: ["ignore", "ignore", "pipe"],
  });
}

async function stopServer(child) {
  if (child.exitCode === null) child.kill("SIGTERM");
  if (child.exitCode === null) await once(child, "exit");
}

async function waitForCard(page) {
  await page.getByText("@mira", { exact: true }).first().waitFor({
    state: "visible",
    timeout: 10_000,
  });
  const openDossier = page.getByText("tap to open", { exact: true });
  if (await openDossier.count()) {
    await openDossier.click();
    await page.waitForTimeout(1_450);
  }
}

await chmod(fakePersome, 0o755);
await mkdir(outputDir, { recursive: true });
const tempRoot = await mkdtemp(path.join(tmpdir(), "whoami-owner-browser-"));
const cardDataDir = path.join(tempRoot, "card-data");
const persomeRoot = path.join(tempRoot, "persome");
await mkdir(persomeRoot, { recursive: true });
await writeFile(
  path.join(persomeRoot, "config.toml"),
  "[mcp]\ntransport='stdio'\n",
);
await writeFile(path.join(persomeRoot, "index.db"), "");

let server = startServer(cardDataDir, persomeRoot);
let browser;
try {
  await waitForServer(server);
  browser = await chromium.launch({
    executablePath: chromePath,
    headless: true,
  });
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

  await page.goto(baseUrl, { waitUntil: "domcontentloaded" });
  await page.getByText("先让这张卡成为你的。", { exact: true }).waitFor();
  const initialText = await page.locator("body").innerText();
  invariant(
    !/Cecilia|@cecilia|Lin · @lin/.test(initialText),
    "Production onboarding exposed a fixture identity.",
  );
  const beforeModels = await page.evaluate(async () => {
    const response = await fetch("/api/models");
    return response.json();
  });
  invariant(beforeModels.devMode === false, "Production unexpectedly enabled dev mode.");
  invariant(beforeModels.models.length === 0, "Production registered a model before setup.");

  await page.locator("[data-setup-name]").fill("Mira");
  await page.locator("[data-setup-handle]").fill("@mira");
  await page.locator("[data-setup-tagline]").fill("MIRA_ONLY_CARD_6C21");
  await page.locator("[data-setup-description]").fill("MIRA_ONLY_IDENTITY_6C21");
  await page.getByText("创建我的 Personal Card", { exact: true }).click();
  await waitForCard(page);

  const ownerModels = await page.evaluate(async () => {
    const response = await fetch("/api/models");
    return response.json();
  });
  invariant(ownerModels.models.length === 1, "Owner setup did not register exactly one model.");
  invariant(
    /^local-[a-f0-9]{20}$/.test(ownerModels.ownerModelId),
    "Owner did not receive a stable local model ID.",
  );
  invariant(
    ownerModels.models[0].id === ownerModels.ownerModelId,
    "The active production model is not the owner model.",
  );
  const stableModelId = ownerModels.ownerModelId;
  const ownerBootstrap = await page.evaluate(async () => {
    const response = await fetch("/api/model/bootstrap");
    return response.json();
  });
  const ownerPayload = JSON.stringify(ownerBootstrap);
  for (const expected of [
    "MIRA_ONLY_CARD_6C21",
    "MIRA_ONLY_IDENTITY_6C21",
    "MIRA_ONLY_ROOT_6C21",
    "MIRA_ONLY_REWIND_6C21",
  ]) {
    invariant(ownerPayload.includes(expected), `Owner Snapshot omitted ${expected}.`);
  }
  invariant(
    !/Cecilia|@cecilia|lin-demo|@lin/.test(ownerPayload),
    "Owner Snapshot leaked a fixture identity.",
  );
  const ownerText = await page.locator("body").innerText();
  for (const expected of ["@mira"]) {
    invariant(ownerText.includes(expected), `Owner Card did not render ${expected}.`);
  }
  invariant(
    !/Cecilia|@cecilia|Lin · @lin|lin-demo/.test(ownerText),
    "Owner Card leaked a fixture identity.",
  );
  await page.screenshot({
    path: path.join(outputDir, "production-owner-mira-1440x1000.png"),
    animations: "disabled",
  });

  await stopServer(server);
  server = startServer(cardDataDir, persomeRoot);
  await waitForServer(server);
  await page.reload({ waitUntil: "domcontentloaded" });
  await waitForCard(page);
  const restartedModels = await page.evaluate(async () => {
    const response = await fetch("/api/models");
    return response.json();
  });
  invariant(
    restartedModels.ownerModelId === stableModelId,
    "Restart changed the owner's Personal Model ID.",
  );
  invariant(
    restartedModels.models.length === 1
      && restartedModels.models[0].handle === "@mira",
    "Restart restored a different user.",
  );
  invariant(consoleErrors.length === 0, consoleErrors.join("\n"));
  console.log(
    `Production owner onboarding/restart passed for ${stableModelId}. `
      + `Screenshot: ${outputDir}`,
  );
} finally {
  if (browser) await browser.close();
  await stopServer(server);
}
