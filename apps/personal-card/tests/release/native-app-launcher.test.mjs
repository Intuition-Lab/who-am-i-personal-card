import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const appRoot = fileURLToPath(new URL("../../", import.meta.url));
const productRoot = fileURLToPath(new URL("../../../../", import.meta.url));

test("production installs a native SwiftUI app with an embedded backend", async () => {
  const [installer, swiftSource, nativeUI, lifecycle, buildScript, packageBuilder] = await Promise.all([
    readFile(path.join(productRoot, "install.sh"), "utf8"),
    readFile(path.join(appRoot, "macos/WhoAmIApp.swift"), "utf8"),
    readFile(path.join(appRoot, "macos/WhoAmINativeUI.swift"), "utf8"),
    readFile(path.join(appRoot, "macos/NativeLifecycle.swift"), "utf8"),
    readFile(path.join(appRoot, "macos/build-native-launcher.sh"), "utf8"),
    readFile(path.join(productRoot, "scripts/build-self-contained-package.sh"), "utf8"),
  ]);

  assert.match(installer, /macos\/build-native-launcher\.sh/);
  assert.doesNotMatch(
    installer,
    /"\$\{source_root\}\/打开 Persome Card\.command"/,
  );
  assert.match(swiftSource, /NSPanel\(/);
  assert.doesNotMatch(swiftSource, /WKWebView|WebKit/);
  assert.match(swiftSource, /api\/app\/health/);
  assert.match(swiftSource, /NSHostingView/);
  assert.match(nativeUI, /struct WhoAmIRootView/);
  assert.match(nativeUI, /rotation3DEffect/);
  assert.match(nativeUI, /api\/model\/connectors/);
  assert.match(nativeUI, /api\/model\/evidence/);
  assert.match(nativeUI, /api\/model\/correct/);
  assert.match(swiftSource, /applicationShouldTerminateAfterLastWindowClosed/);
  assert.match(swiftSource, /NSStatusBar\.system\.statusItem/);
  assert.match(swiftSource, /\.accessory/);
  assert.match(buildScript, /for architecture in arm64 x86_64/);
  assert.match(buildScript, /\$\{architecture\}-apple-macos13\.0/);
  assert.match(buildScript, /codesign --verify --strict/);
  assert.match(buildScript, /WhoAmIManagedInstall/);
  assert.match(buildScript, /--bootstrap/);
  assert.match(buildScript, /WhoAmIBootstrapInstall/);
  assert.match(swiftSource, /beginNativeBootstrap/);
  assert.match(swiftSource, /NativeInstallerView/);
  assert.doesNotMatch(swiftSource, /NSWorkspace\.shared\.open\(installerURL\)/);
  assert.match(lifecycle, /install\.sh/);
  assert.match(lifecycle, /"--non-interactive"/);
  assert.match(lifecycle, /Applications\/Who Am I\.app/);
  assert.match(packageBuilder, /--bootstrap/);
  assert.match(packageBuilder, /Who Am I\.app/);
  assert.match(packageBuilder, /Contents\/Resources\/product/);
  assert.match(packageBuilder, /backend_embedded_in_app/);
});
