import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const appRoot = fileURLToPath(new URL("../../", import.meta.url));

test("Persome packages a real Electron app without development identities", async () => {
  const manifest = JSON.parse(await readFile(path.join(appRoot, "package.json"), "utf8"));
  assert.equal(manifest.main, "electron/main.mjs");
  assert.equal(manifest.build.appId, "ai.intuition.persome");
  assert.equal(manifest.build.productName, "Persome");
  assert.ok(manifest.build.files.includes("dist/renderer/**/*"));
  assert.ok(manifest.build.files.includes("electron/**/*"));
  assert.equal(
    manifest.build.files.some((entry) => /fixtures|development|prototypes|tests/.test(entry)),
    false,
  );
  assert.ok(manifest.build.extraResources.some((entry) =>
    entry.to === "product-installer"
    && entry.filter.includes("runtime.lock")
    && entry.filter.includes("install.sh")));
});

test("the Electron shell is isolated from the legacy HTML service and old Card data", async () => {
  const source = await readFile(path.join(appRoot, "electron/main.mjs"), "utf8");
  assert.match(source, /WHOAMI_CARD_PORT \|\| "8773"/);
  assert.match(source, /WHOAMI_CARD_DATA_DIR:[^\n]+app\.getPath\("userData"\)/);
  assert.match(source, /contextIsolation: true/);
  assert.match(source, /nodeIntegration: false/);
  assert.match(source, /sandbox: true/);
  assert.match(source, /desktopRenderer === "electron-v1"/);
  assert.match(source, /title: "Persome",[\s\S]*?frame: false/);
  assert.doesNotMatch(source, /titleBarStyle: "hiddenInset"|trafficLightPosition:/);
  assert.match(source, /app\.on\("activate", showQuickWindow\)/);
  assert.match(source, /globalShortcut\.register\(globalAccelerator, toggleQuickWindow\);\s*showQuickWindow\(\);/);
  assert.doesNotMatch(source, /await startServer\(\);\s*createMainWindow\(\);/);
  assert.match(source, /createMainWindow\(route\)/);
  assert.match(source, /rendererUrl\("main", initialRoute\)/);
});

test("the packaged first-run command uses the pinned in-app Runtime installer", async () => {
  const command = await readFile(
    path.join(appRoot, "设置我的 Personal Model.command"),
    "utf8",
  );
  assert.match(command, /product-installer\/install\.sh/);
  assert.match(command, /--interactive --runtime-only/);
  assert.doesNotMatch(command, /\/releases\/latest|\/archive\/refs\/heads\/|git clone/);
});
