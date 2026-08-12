import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { _electron as electron } from "playwright-core";

const projectRoot = fileURLToPath(new URL("../../", import.meta.url));
const testRoot = await mkdtemp(path.join(tmpdir(), "persome-electron-shell-"));
const port = 19000 + (process.pid % 1000);

function invariant(condition, message) {
  if (!condition) throw new Error(message);
}

let electronApp;
try {
  electronApp = await electron.launch({
    args: [
      path.join(projectRoot, "electron/main.mjs"),
      `--user-data-dir=${path.join(testRoot, "electron-user-data")}`,
    ],
    cwd: projectRoot,
    env: {
      ...process.env,
      WHOAMI_CARD_DATA_DIR: path.join(testRoot, "card-data"),
      WHOAMI_CARD_PORT: String(port),
      WHOAMI_DEV_MODE: "1",
      WHOAMI_PROVIDER_MODE: "fixture",
    },
    timeout: 30_000,
  });

  const quickWindow = await electronApp.firstWindow({ timeout: 30_000 });
  await quickWindow.waitForLoadState("networkidle");
  invariant(new URL(quickWindow.url()).searchParams.get("surface") === "quick", "Persome did not launch into Spotlight.");
  invariant(electronApp.windows().length === 1, "Persome created the Dashboard before the user expanded Spotlight.");
  await quickWindow.getByRole("textbox", { name: "Jot or ask Persome" }).waitFor();
  const openApp = quickWindow.getByRole("button", { name: "Open the full Persome app" });
  await openApp.waitFor();

  const dashboardPromise = electronApp.waitForEvent("window", { timeout: 30_000 });
  await openApp.click();
  const dashboard = await dashboardPromise;
  await dashboard.waitForLoadState("networkidle");
  const dashboardUrl = new URL(dashboard.url());
  invariant(dashboardUrl.searchParams.get("surface") === "main", "Open app did not expand into the Dashboard.");
  invariant(dashboardUrl.searchParams.get("route") === "home", "Dashboard did not open on the Personal Card home route.");
  await dashboard.locator(".card-stage").waitFor();
  invariant(await dashboard.locator(".titlebar").isVisible(), "The frameless Dashboard header is missing.");

  const windowState = await electronApp.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows().map((window) => ({
      title: window.getTitle(),
      visible: window.isVisible(),
    }))
  );
  invariant(windowState.some((window) => window.title === "Persome" && window.visible), "Dashboard BrowserWindow is not visible.");
  console.log("Electron launch flow passed: Spotlight first, Dashboard only after Open app.");
} finally {
  await electronApp?.close();
}
