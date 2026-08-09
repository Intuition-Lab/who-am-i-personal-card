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
  assert.match(swiftSource, /visibleFrame\.height - verticalMargin \* 2/);
  assert.match(swiftSource, /window\.setContentSize\(targetSize\)/);
  assert.match(swiftSource, /isMovableByWindowBackground = false/);
  assert.match(swiftSource, /showSearchFromStatusItem/);
  assert.match(swiftSource, /showAskFromStatusItem/);
  assert.match(swiftSource, /showMemorySkyFromStatusItem/);
  assert.match(swiftSource, /showShareFromStatusItem/);
  assert.doesNotMatch(nativeUI, /private struct NativeTopBar/);
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
  assert.match(buildScript, /APP_ICON_SOURCE_DIRECTORY/);
  assert.match(buildScript, /Contents.*Resources/s);
  assert.match(buildScript, /APP_ICON_RESOURCES_DIRECTORY/);
  for (const icon of [
    "chatgpt.png",
    "chrome.png",
    "claude.png",
    "coast.png",
    "finder.png",
    "lark.png",
    "notes.png",
    "terminal.png",
    "wechat.png",
  ]) {
    assert.match(buildScript, new RegExp(icon.replace(".", "\\.")));
  }
  assert.match(nativeUI, /Bundle\.main\.resourceURL/);
  assert.match(nativeUI, /appendingPathComponent\("AppIcons"/);
  assert.match(nativeUI, /WHOAMI_VISUAL_QA_ACTIVE/);
  assert.match(swiftSource, /whoAmIVisualQAActive/);
  assert.match(nativeUI, /onContinuousHover/);
  assert.match(nativeUI, /func openRewind\(dayID:/);
  assert.match(nativeUI, /state\.openRewind\(dayID: item\.dayId\)/);
  assert.match(packageBuilder, /--bootstrap/);
  assert.match(packageBuilder, /Who Am I\.app/);
  assert.match(packageBuilder, /Contents\/Resources\/product/);
  assert.match(packageBuilder, /backend_embedded_in_app/);
  assert.match(packageBuilder, /codesign --remove-signature/);
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
    "NativeFlowLayout",
    "NativeAppTopBar",
    "NativeAppTopMenu",
    "NativeRewindFilters",
    "NativeRewindDayBar",
    "NativeMonthCalendar",
    "NativeRewindHighlights",
    "NativeRewindTelevision",
    "NativeTelevisionKnob",
    "NativeMemorySky",
    "NativeConstellationTheme",
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
    "search memories…",
    "日历与记忆星图",
    "今天写进 Personal Model",
    "值得回去的瞬间",
    "每件事只出现一次 · 点一下回到画面",
    "FACE · 面",
    "VOLUME · 体",
    "ROOT · 根",
    "当天没有可用的画面",
    "0 / 0",
    "Persome · 已连接",
    "正在记录 · 暂停 1 小时",
    "ROOT · 今天留下的一句",
    "ROOT · 我是谁",
    "← → 巡星",
    "亮星可点 · ← → 巡星 · 点星座名查看模型推断",
    "SAME MODEL · PRIVATE INSIDE / PUBLIC OUTSIDE",
    "划线分享",
    "打开 Evidence",
  ]) {
    assert.match(nativeUI, new RegExp(detail));
  }
  assert.doesNotMatch(nativeUI, /WKWebView|WebKit/);
  assert.match(nativeUI, /state\.isMemorySkyOpen[\s\S]*accessibilityHidden/);
  assert.match(nativeUI, /onExitCommand/);
  assert.match(nativeUI, /state\.rewindDayRequest = nil/);
  assert.match(nativeUI, /nativeMonthName\(referenceDate\)/);
  assert.match(nativeUI, /nativeDayLetterParts/);
  assert.match(nativeUI, /LazyVStack\(spacing: 0\)/);
  assert.match(nativeUI, /NativeFlowTrailingKey/);
  assert.match(nativeUI, /let weekCount = 28/);
  assert.match(nativeUI, /frame\(width: 430, height: 430 \/ 1\.586\)/);
  assert.match(nativeUI, /\(28, 40, 16, 34\)/);
  assert.match(nativeUI, /\(66, 56, 14, 26\)/);
  assert.match(nativeUI, /\(46, 72, 11, 18\)/);
  assert.match(nativeUI, /\(76, 26, 9, 12\)/);
  assert.doesNotMatch(nativeUI, /COPY CARD/);
});
