import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const appRoot = fileURLToPath(new URL("../../", import.meta.url));
const productRoot = fileURLToPath(new URL("../../../../", import.meta.url));

test("production installs a native SwiftUI app with an embedded backend", async () => {
  const [
    installer,
    swiftSource,
    nativeUI,
    buildScript,
    packageBuilder,
    signingScript,
    notarizeScript,
    entitlements,
  ] = await Promise.all([
    readFile(path.join(productRoot, "install.sh"), "utf8"),
    readFile(path.join(appRoot, "macos/WhoAmIApp.swift"), "utf8"),
    readFile(path.join(appRoot, "macos/WhoAmINativeUI.swift"), "utf8"),
    readFile(path.join(appRoot, "macos/build-native-launcher.sh"), "utf8"),
    readFile(path.join(productRoot, "scripts/build-self-contained-package.sh"), "utf8"),
    readFile(path.join(productRoot, "scripts/sign-macos-release.sh"), "utf8"),
    readFile(path.join(productRoot, "scripts/notarize-macos-release.sh"), "utf8"),
    readFile(path.join(appRoot, "macos/WhoAmI.entitlements"), "utf8"),
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
  assert.match(buildScript, /codesign --verify --deep --strict/);
  assert.match(buildScript, /--options runtime/);
  assert.match(buildScript, /--entitlements/);
  assert.match(buildScript, /WhoAmIManagedInstall/);
  assert.match(buildScript, /--bootstrap/);
  assert.match(buildScript, /WhoAmIBootstrapInstall/);
  assert.match(swiftSource, /installAndOpenNativeApp/);
  assert.match(swiftSource, /Install Who Am I\.command/);
  assert.match(swiftSource, /Applications.*Who Am I\.app/s);
  assert.match(packageBuilder, /--bootstrap/);
  assert.match(packageBuilder, /Who Am I\.app/);
  assert.match(packageBuilder, /Contents\/Resources\/product/);
  assert.match(packageBuilder, /backend_embedded_in_app/);
  assert.match(packageBuilder, /--release-signing/);
  assert.match(packageBuilder, /sign-macos-release\.sh/);
  assert.match(packageBuilder, /notarize-macos-release\.sh/);
  assert.match(signingScript, /Developer ID Application/);
  assert.match(signingScript, /codesign --verify --deep --strict/);
  assert.match(notarizeScript, /notarytool submit/);
  assert.match(notarizeScript, /stapler validate/);
  assert.match(notarizeScript, /spctl --assess/);
  assert.doesNotMatch(entitlements, /com\.apple\.security\./);
});
