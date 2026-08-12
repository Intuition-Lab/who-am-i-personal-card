import { spawn } from "node:child_process";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { chromium } from "playwright-core";

const projectRoot = fileURLToPath(new URL("../../", import.meta.url));
const chromePath = process.env.CHROME_PATH
  || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const port = Number(process.env.PERSOME_RENDERER_TEST_PORT || 18873);
const baseUrl = `http://127.0.0.1:${port}`;

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

async function waitForServer(child) {
  for (let attempt = 0; attempt < 120; attempt += 1) {
    if (child.exitCode !== null) throw new Error("Persome server exited early.");
    try {
      const response = await fetch(`${baseUrl}/api/app/health`);
      if (response.ok) return;
    } catch {
      // Keep waiting for the loopback service.
    }
    await new Promise((resolve) => setTimeout(resolve, 30));
  }
  throw new Error("Timed out waiting for the Persome renderer test server.");
}

const cardDataDir = await mkdtemp(path.join(tmpdir(), "persome-electron-renderer-"));
const server = spawn(process.execPath, ["persome-card-server.mjs"], {
  cwd: projectRoot,
  env: {
    ...process.env,
    WHOAMI_CARD_DATA_DIR: cardDataDir,
    WHOAMI_CARD_PORT: String(port),
    WHOAMI_DEV_MODE: "1",
    WHOAMI_PROVIDER_MODE: "fixture",
  },
  stdio: ["ignore", "ignore", "pipe"],
});

let browser;
try {
  await waitForServer(server);
  browser = await chromium.launch({ executablePath: chromePath, headless: true });
  const page = await browser.newPage({ viewport: { width: 1180, height: 820 } });
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });

  await page.goto(`${baseUrl}/app/?surface=main&route=home`, { waitUntil: "networkidle" });
  await page.getByText("@cecilia", { exact: true }).waitFor();
  invariant(await page.locator(".card-stage").isVisible(), "Personal Card is missing.");
  invariant(await page.locator(".quick-box").isVisible(), "Quick Box is missing.");

  await page.locator(".card-stage").click({ position: { x: 250, y: 150 } });
  invariant(await page.locator(".card-stage").getAttribute("aria-pressed") === "true", "Card did not flip.");
  await page.getByRole("button", { name: "Expand Map" }).click();
  await page.getByText("Why it understands you this way", { exact: true }).waitFor();

  await page.goto(`${baseUrl}/app/?surface=main&route=home`, { waitUntil: "networkidle" });
  const input = page.getByRole("textbox", { name: "Jot or ask Persome" });
  await input.fill("what was I working on?");
  await page.getByText("Question detected · switched to Ask", { exact: false }).waitFor();
  invariant(await page.locator(".quick-box").getAttribute("data-mode") === "ask", "Question did not switch to Ask.");

  await page.goto(`${baseUrl}/app/?surface=main&route=${encodeURIComponent("map:rewind:week")}`, { waitUntil: "networkidle" });
  invariant(await page.locator(".week-day:not(:disabled)").count() === 1, "Week duplicated a captured day into gaps.");
  await page.locator(".week-day:not(:disabled)").click();
  invariant(await page.locator(".tv").isVisible(), "Week did not open the selected Rewind Day.");

  await page.goto(`${baseUrl}/app/?surface=main&route=${encodeURIComponent("map:rewind:month")}`, { waitUntil: "networkidle" });
  invariant(await page.locator("button.month-day:not(:disabled)").count() === 1, "Month duplicated a captured day into gaps.");

  await page.goto(`${baseUrl}/app/?surface=main&route=swipe`, { waitUntil: "networkidle" });
  await page.getByText("Same you, every AI", { exact: true }).waitFor();
  invariant(await page.locator(".agent-report-card").isVisible(), "Agent Report is too deeply hidden.");
  const connectedAgent = page.locator(".agent.connected").first();
  const connectedAgentName = await connectedAgent.locator("strong").innerText();
  await connectedAgent.click();
  await page.getByRole("button", { name: "Review access" }).click();
  await page.getByRole("button", { name: "Revoke access" }).click();
  await page.locator(".toast.show").waitFor();
  const revokeToast = await page.locator(".toast.show").innerText();
  invariant(revokeToast.endsWith("access revoked"), `Revoke did not return a verified receipt: ${revokeToast}`);
  const revokedAgent = page.locator(".agent", { hasText: connectedAgentName });
  invariant(!(await revokedAgent.getAttribute("class")).includes("connected"), "Revoked AI remained connected in the UI.");
  invariant(errors.length === 0, errors.join("\n"));
  console.log("Electron renderer interaction and honest-gap checks passed.");
} finally {
  if (browser) await browser.close();
  if (server.exitCode === null) server.kill("SIGTERM");
}
