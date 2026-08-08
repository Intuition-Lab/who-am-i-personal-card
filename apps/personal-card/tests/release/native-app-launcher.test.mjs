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
  assert.match(nativeUI, /enum NativeRequestPhase/);
  assert.match(nativeUI, /case insufficient/);
  assert.match(nativeUI, /Personal Model 推断/);
  assert.match(nativeUI, /记录事实/);
  assert.match(nativeUI, /生成内容/);
  assert.match(nativeUI, /延续建议/);
  assert.match(nativeUI, /复制卡片/);
  assert.match(nativeUI, /这条 Evidence 已失效/);
  assert.match(nativeUI, /本机服务未启动/);
  assert.doesNotMatch(nativeUI, /Button\(copied \? "Copied" : "Share"\)/);
  assert.match(swiftSource, /applicationShouldTerminateAfterLastWindowClosed/);
  assert.match(swiftSource, /NSStatusBar\.system\.statusItem/);
  assert.match(swiftSource, /positionSpotlightPanel/);
  assert.match(swiftSource, /statusButton\.convert/);
  assert.match(swiftSource, /showSearchFromStatusItem/);
  assert.match(swiftSource, /showAskFromStatusItem/);
  assert.match(swiftSource, /showMemorySkyFromStatusItem/);
  assert.match(swiftSource, /showShareFromStatusItem/);
  assert.doesNotMatch(nativeUI, /private struct NativeTopBar/);
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

test("native app preserves the original V5 interaction surfaces without a WebView", async () => {
  const nativeUI = await readFile(
    path.join(appRoot, "macos/WhoAmINativeUI.swift"),
    "utf8",
  );

  for (const surface of [
    "NativeHeroCard",
    "NativeCardMaterial",
    "NativeNowPanel",
    "NativeShareView",
    "NativeIdentityView",
    "NativeYearHeatmap",
    "NativeMonthCalendar",
    "NativeRewindTelevision",
    "NativeMemorySky",
    "NativeCorrectionToast",
    "NativeConnectorDock",
    "NativeConnectorSwipe",
    "NativeReportsView",
    "NativeEvidencePresentation",
    "NativeSetupView",
  ]) {
    assert.match(nativeUI, new RegExp(`struct ${surface}`));
  }

  for (const detail of [
    "Swipe your card",
    "MEMORY SKY",
    'case constellation = "星座"',
    'case dust = "星尘"',
    'case time = "时间"',
    "过去 · 现在 · 未来",
    "Swipe your card",
    "\\+1 颗星",
    'case "ceramic"',
    'case "klein"',
    'case "graphite"',
    "Search this day",
    "今天写进 Personal Model",
    "ROOT · 今天留下的一句",
    "ROOT · 我是谁",
    "← → 巡星",
    "SAME MODEL · PRIVATE INSIDE / PUBLIC OUTSIDE",
    "划线分享",
    "打开 Evidence",
  ]) {
    assert.match(nativeUI, new RegExp(detail));
  }
  assert.doesNotMatch(nativeUI, /WKWebView|WebKit/);
});
