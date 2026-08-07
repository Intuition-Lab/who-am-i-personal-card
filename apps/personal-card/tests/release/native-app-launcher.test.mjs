import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const appRoot = fileURLToPath(new URL("../../", import.meta.url));
const productRoot = fileURLToPath(new URL("../../../../", import.meta.url));

test("production installs a native app window instead of a browser launcher", async () => {
  const [installer, swiftSource, buildScript] = await Promise.all([
    readFile(path.join(productRoot, "install.sh"), "utf8"),
    readFile(path.join(appRoot, "macos/WhoAmIApp.swift"), "utf8"),
    readFile(path.join(appRoot, "macos/build-native-launcher.sh"), "utf8"),
  ]);

  assert.match(installer, /macos\/build-native-launcher\.sh/);
  assert.doesNotMatch(
    installer,
    /"\$\{source_root\}\/打开 Persome Card\.command"/,
  );
  assert.match(swiftSource, /NSWindow\(/);
  assert.match(swiftSource, /WKWebView\(/);
  assert.match(swiftSource, /api\/app\/health/);
  assert.match(swiftSource, /webView\?\.load\(URLRequest\(url: serverURL\)\)/);
  assert.match(swiftSource, /applicationShouldTerminateAfterLastWindowClosed/);
  assert.match(buildScript, /for architecture in arm64 x86_64/);
  assert.match(buildScript, /\$\{architecture\}-apple-macos13\.0/);
  assert.match(buildScript, /codesign --verify --strict/);
  assert.match(buildScript, /WhoAmIManagedInstall/);
});
