import { spawn } from "node:child_process";
import { mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { chromium } from "playwright-core";

const projectRoot = fileURLToPath(new URL("../../", import.meta.url));
const chromePath = process.env.CHROME_PATH
  || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const port = Number(process.env.WHOAMI_TEST_PORT || 18772);
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
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (child.exitCode !== null) {
      throw new Error(`Personal Card server exited with ${child.exitCode}`);
    }
    try {
      const response = await fetch(baseUrl, { method: "HEAD" });
      if (response.ok) return;
    } catch {
      // Continue until the child is listening.
    }
    await new Promise((resolve) => setTimeout(resolve, 30));
  }
  throw new Error("Timed out waiting for the Personal Card server.");
}

async function waitForCard(page, handle) {
  await page.getByText(handle, { exact: true }).first().waitFor({
    state: "visible",
    timeout: 10_000,
  });
  const openDossier = page.getByText("tap to open", { exact: true });
  if (await openDossier.count()) {
    await openDossier.click();
    await page.waitForTimeout(1_450);
  }
}

async function openHome(page, modelId = "cecilia", access = "owner") {
  await page.goto(
    `${baseUrl}/?dev=1&model=${encodeURIComponent(modelId)}&access=${access}`,
    { waitUntil: "domcontentloaded" },
  );
  await waitForCard(page, modelId === "cecilia" ? "@cecilia" : "@lin");
}

async function capture(page, name) {
  await page.screenshot({
    path: path.join(outputDir, `${name}-1440x1000.png`),
    animations: "disabled",
  });
}

async function closeOpenMenu(page) {
  await page.getByRole("button", { name: "Open card menu" }).click({
    force: true,
  });
  await page.waitForTimeout(80);
}

async function clickVisible(locator) {
  const count = await locator.count();
  for (let index = 0; index < count; index += 1) {
    const candidate = locator.nth(index);
    if (await candidate.isVisible()) {
      await candidate.click();
      return;
    }
  }
  throw new Error("No visible element matched the requested interaction.");
}

await mkdir(outputDir, { recursive: true });
const server = spawn(process.execPath, ["persome-card-server.mjs"], {
  cwd: projectRoot,
  env: {
    ...process.env,
    WHOAMI_CARD_PORT: String(port),
    WHOAMI_PROVIDER_MODE: "fixture",
    WHOAMI_DEV_MODE: "1",
  },
  stdio: ["ignore", "ignore", "pipe"],
});

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
  const failedResources = [];
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
  page.on("response", (response) => {
    if (
      response.status() >= 400
      && !["fetch", "xhr"].includes(response.request().resourceType())
      && !/%7B%7B|favicon\.ico/i.test(response.url())
    ) {
      failedResources.push(`${response.status()} ${response.url()}`);
    }
  });

  await openHome(page);
  await capture(page, "home");
  await capture(page, "runtime-cecilia");

  const initialUrl = page.url();
  await page.evaluate(async () => {
    try {
      await window.whoamiSwitchModel("missing-model", { access: "public" });
    } catch {
      // The UI must retain the last complete Snapshot and show the failure.
    }
  });
  await page.getByText("Persome · 切换失败", { exact: true }).waitFor();
  invariant(
    await page.getByText("@cecilia", { exact: true }).first().isVisible(),
    "A failed switch replaced the prior Cecilia Snapshot.",
  );

  await page.getByRole("button", { name: "Open card menu" }).click();
  await page.getByText("Lin · @lin", { exact: true }).click();
  await page.getByText("@lin", { exact: true }).first().waitFor();
  invariant(page.url() === initialUrl, "Runtime model switch unexpectedly reloaded the page.");
  await closeOpenMenu(page);
  const linHomeText = await page.locator("body").innerText();
  for (const forbidden of [
    "@cecilia",
    "Personal Card 的上一版",
    "继续 Personal Card",
    "cecilia:event",
  ]) {
    invariant(!linHomeText.includes(forbidden), `Lin Home leaked ${forbidden}`);
  }
  invariant(linHomeText.includes("整理城市夜间导航原型"), "Lin Now did not render.");
  await capture(page, "runtime-lin");

  await clickVisible(page.getByText("时间", { exact: true }));
  await page.waitForTimeout(150);
  await clickVisible(page.getByText("7", { exact: true }));
  await page.getByText("夜间导航 · 田野记录", { exact: true }).waitFor();
  const linRewindText = await page.locator("body").innerText();
  invariant(!linRewindText.includes("Personal Card · 实时内容"), "Lin Rewind leaked Cecilia.");
  await page.keyboard.press("Escape");

  await page.getByRole("button", { name: "Open card menu" }).click();
  await page.getByText("分享这张卡", { exact: true }).click();
  await page.getByText("My Page · Identity ↗", { exact: true }).click();
  const linIdentityText = await page.locator("body").innerText();
  invariant(linIdentityText.includes("Urban interaction designer"), "Lin Identity did not render.");
  invariant(!linIdentityText.includes("Product person building Who Am I"), "Lin Identity leaked Cecilia.");
  await page.keyboard.press("Escape");

  await page.getByText("Swipe your card", { exact: true }).click();
  await page.getByText("夜间导航原型 · Context", { exact: true }).waitFor();
  const connectorText = await page.locator("body").innerText();
  invariant(connectorText.includes("@lin"), "Lin Connector pass did not use @lin.");
  invariant(!connectorText.includes("@cecilia"), "Lin Connector pass leaked @cecilia.");
  await page.locator(".wConnectorAdd").click();
  await page.getByText("Other Agent", { exact: true }).waitFor();
  await page.locator(".wReportHead").first().click();
  await page.getByText("lin-demo:event:2026-08-07:01", { exact: true }).waitFor();
  const linReportText = await page.locator("body").innerText();
  invariant(!linReportText.includes("cecilia:"), "Lin Report/Evidence leaked Cecilia receipts.");

  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: "Open card menu" }).click();
  await page.getByText("Cecilia · @cecilia", { exact: true }).click();
  await page.getByText("@cecilia", { exact: true }).first().waitFor();
  await closeOpenMenu(page);

  await page.getByText("Swipe your card", { exact: true }).click();
  await page.getByText("继续 Personal Card · Context", { exact: true }).waitFor();
  await capture(page, "swipe");
  await capture(page, "report-collapsed");
  await page.locator(".wReportHead").first().click();
  await capture(page, "report-expanded");
  await page.keyboard.press("Escape");

  await clickVisible(page.getByText("时间", { exact: true }));
  await capture(page, "rewind");
  await page.keyboard.press("Escape");

  await page.locator('[title^="巡星"]').click();
  await capture(page, "sky");
  await page.keyboard.press("Escape");

  await page.getByRole("button", { name: "Open card menu" }).click();
  await page.getByText("分享这张卡", { exact: true }).click();
  await page.getByText("My Page · Identity ↗", { exact: true }).click();
  await capture(page, "identity");

  const publicPage = await context.newPage();
  await publicPage.goto(`${baseUrl}/?model=lin-demo&public=1`, {
    waitUntil: "domcontentloaded",
  });
  await waitForCard(publicPage, "@lin");
  const publicResponse = await publicPage.evaluate(async () => {
    const response = await fetch("/api/model/reports");
    return { status: response.status, body: await response.json() };
  });
  invariant(publicResponse.status === 403, "Public visitor could read reports.");
  invariant(publicResponse.body.code === "SCOPE_REQUIRED", "Public denial was not scope-bound.");

  invariant(
    consoleErrors.length === 0 && failedResources.length === 0,
    [
      ...consoleErrors,
      ...failedResources,
    ].join("\n"),
  );
  console.log(`Browser switch/isolation passed. Screenshots: ${outputDir}`);
} finally {
  if (browser) await browser.close();
  if (server.exitCode === null) server.kill("SIGTERM");
}
