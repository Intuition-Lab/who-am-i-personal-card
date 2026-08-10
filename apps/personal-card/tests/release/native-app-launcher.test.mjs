import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const appRoot = fileURLToPath(new URL("../../", import.meta.url));
const productRoot = fileURLToPath(new URL("../../../../", import.meta.url));

test("production installs a native SwiftUI app with an embedded backend", async () => {
  const [installer, swiftSource, nativeUI, buildScript, packageBuilder] = await Promise.all([
    readFile(path.join(productRoot, "install.sh"), "utf8"),
    readFile(path.join(appRoot, "macos/WhoAmIApp.swift"), "utf8"),
    readFile(path.join(appRoot, "macos/WhoAmINativeUI.swift"), "utf8"),
    readFile(path.join(appRoot, "macos/build-native-launcher.sh"), "utf8"),
    readFile(path.join(productRoot, "scripts/build-self-contained-package.sh"), "utf8"),
  ]);

  assert.match(installer, /macos\/build-native-launcher\.sh/);
  assert.doesNotMatch(
    installer,
    /"\$\{source_root\}\/打开 Persome Card\.command"/,
  );
  assert.match(swiftSource, /NSPanel\(/);
  assert.match(swiftSource, /styleMask: \[\.borderless\]/);
  assert.doesNotMatch(swiftSource, /WKWebView|WebKit/);
  assert.match(swiftSource, /api\/app\/health/);
  assert.match(swiftSource, /NSHostingView/);
  assert.match(nativeUI, /struct WhoAmIRootView/);
  assert.match(nativeUI, /\.frame\(minWidth: 900, minHeight: 640\)\s*\.ignoresSafeArea\(\)/);
  assert.doesNotMatch(
    nativeUI,
    /struct WhoAmIRootView[\s\S]*?NativeAppTopBar\(state:/,
  );
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
  assert.match(swiftSource, /width: min\(1_280, max\(760,/);
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
  assert.match(buildScript, /LSArchitecturePriority\.0.*arm64/);
  assert.match(buildScript, /LSArchitecturePriority\.1.*x86_64/);
  assert.match(buildScript, /LSRequiresNativeExecution.*true/);
  assert.match(buildScript, /codesign --verify --strict/);
  assert.match(buildScript, /WhoAmIManagedInstall/);
  assert.match(buildScript, /--bootstrap/);
  assert.match(buildScript, /WhoAmIBootstrapInstall/);
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
  assert.match(nativeUI, /WHOAMI_VISUAL_QA_SECTION/);
  assert.match(nativeUI, /WHOAMI_VISUAL_QA_PRESENTATION/);
  assert.match(nativeUI, /WHOAMI_VISUAL_QA_SERVER_URL/);
  assert.match(nativeUI, /WHOAMI_VISUAL_QA_SNAPSHOT_PATH/);
  assert.match(nativeUI, /WHOAMI_VISUAL_QA_MODEL_ID/);
  assert.match(nativeUI, /path: "api\/session\/model"/);
  assert.match(swiftSource, /whoAmIVisualQAActive/);
  assert.match(swiftSource, /state\.selectedSection = section/);
  assert.match(swiftSource, /"rewind-day:"/);
  assert.match(swiftSource, /"rewind-tv:"/);
  assert.match(swiftSource, /"rewind-tv-fallback:"/);
  assert.match(swiftSource, /"rewind-root:"/);
  assert.match(swiftSource, /"memory-sky-evidence:"/);
  assert.match(swiftSource, /"share-fact-evidence:"/);
  assert.match(swiftSource, /presentation == "share"/);
  assert.match(nativeUI, /presentation\.hasPrefix\("setup:"\)/);
  assert.match(nativeUI, /requested == "profile-saved"/);
  assert.match(swiftSource, /state\.rewindDayRequest = dayID/);
  assert.match(nativeUI, /presentation\.hasPrefix\("rewind-tv:"\)/);
  assert.match(nativeUI, /presentation\.hasPrefix\("rewind-tv-fallback:"\)/);
  assert.match(nativeUI, /rewind-day-root/);
  assert.match(swiftSource, /scheduleVisualQASnapshotIfNeeded/);
  assert.match(swiftSource, /bitmapImageRepForCachingDisplay/);
  assert.match(swiftSource, /1_100_000_000/);
  assert.match(swiftSource, /visualQAServerOverride != nil/);
  assert.match(nativeUI, /onContinuousHover/);
  assert.doesNotMatch(nativeUI, /pinnedViews: \[\.sectionHeaders\]/);
  assert.match(nativeUI, /daySearchAnswer/);
  assert.match(nativeUI, /已定位到/);
  assert.match(nativeUI, /Array\(output\.suffix\(3\)\)/);
  assert.match(nativeUI, /highlight\.index \+ 1/);
  assert.match(nativeUI, /geometry\.size\.height - 290/);
  assert.match(nativeUI, /events\.first\?\.detail\?\.trimmedNonEmpty/);
  assert.match(nativeUI, /VStack\(spacing: 15\)[\s\S]*?\.offset\(y: 7\)/);
  assert.match(nativeUI, /\.frame\(height: 22, alignment: \.topLeading\)/);
  assert.match(nativeUI, /VStack\(alignment: \.leading, spacing: 16\)/);
  assert.match(nativeUI, /let documentWidth = min\(960, max\(0, cardWidth - 76\)\)/);
  assert.match(nativeUI, /\.frame\(width: documentWidth, alignment: \.topLeading\)/);
  assert.match(nativeUI, /day\.portrait\?\.trimmedNonEmpty/);
  assert.match(
    nativeUI,
    /Text\(day\.title \?\? day\.id\)[\s\S]*?font\(\.custom\("Iowan Old Style", size: 42\)\)/,
  );
  assert.match(
    nativeUI,
    /Text\(nativeFullDayLabel\(dayID\)\)[\s\S]*?font\(\.custom\("Iowan Old Style", size: 42\)\)/,
  );
  assert.match(nativeUI, /\.frame\(height: 23\)\s*\.padding\(\.top, 6\)\s*\.padding\(\.bottom, 7\)/);
  assert.match(
    nativeUI,
    /Text\("Swipe your card"\)[\s\S]*?font\(\.custom\("Iowan Old Style", size: 31\)\)/,
  );
  assert.match(
    nativeUI,
    /Button \{\s*state\.selectedSection = \.connectors\s*\} label: \{\s*Text\("Swipe your card"\)/,
  );
  assert.doesNotMatch(nativeUI, /isConnectorDockOpen|NativeConnectorDock/);
  assert.match(nativeUI, /\.frame\(height: 40\)/);
  assert.match(
    nativeUI,
    /HStack\(spacing: 8\)[\s\S]*?\.overlay\(alignment: \.topTrailing\) \{[\s\S]*?NativeConnectorPicker\(\)/,
  );
  assert.match(nativeUI, /formatter\.dateFormat = "M月d日EEEE"/);
  assert.match(nativeUI, /nativeConnectorDisplayName\(report\.connectorId\)/);
  assert.match(nativeUI, /nativeReportTime\(report\.updatedAt\)/);
  assert.match(nativeUI, /\$0\.kind\?\.lowercased\(\) == "lead"/);
  assert.match(nativeUI, /\$0\.kind\?\.lowercased\(\) == "understanding"/);
  assert.ok(nativeUI.includes('Text("1 条依据 · \\(report.timeRange'));
  assert.match(nativeUI, /Button\("回到当天"\)/);
  assert.match(nativeUI, /NativeTelevisionKnob\(rotation: 28\)/);
  assert.match(nativeUI, /NativeTelevisionKnob\(rotation: 80\)/);
  assert.match(nativeUI, /reliableFutureItems/);
  assert.match(nativeUI, /Button \{ selectFuture\(dayID\) \}/);
  assert.match(nativeUI, /func openRewind\(dayID:/);
  assert.match(nativeUI, /state\.openRewind\(dayID: item\.dayId\)/);
  assert.match(swiftSource, /installAndOpenNativeApp/);
  assert.match(swiftSource, /Install Who Am I\.command/);
  assert.match(swiftSource, /Applications.*Who Am I\.app/s);
  assert.match(packageBuilder, /--bootstrap/);
  assert.match(packageBuilder, /Who Am I\.app/);
  assert.match(packageBuilder, /Contents\/Resources\/product/);
  assert.match(packageBuilder, /backend_embedded_in_app/);
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
    "NativeShareFactOverlay",
    "NativeShareBackdropBlur",
    "NativeShareFactCard",
    "NativeShareMiniGlyph",
    "NativeShareFactExport",
    "NativeIdentityView",
    "NativeYearHeatmap",
    "NativeFlowLayout",
    "NativeAppTopBar",
    "NativeAppTopMenu",
    "NativeRewindFilters",
    "NativeRewindDayBar",
    "NativeRewindFutureDayBar",
    "NativeRewindFutureDocument",
    "NativeRewindMonthGrid",
    "NativeMonthCalendar",
    "NativeMonthDayPeek",
    "NativeRewindHighlights",
    "NativeRewindTelevision",
    "NativeTelevisionKnob",
    "RewindFrameSnapshot",
    "NativeMemorySky",
    "NativeConstellationTheme",
    "NativeCorrectionToast",
    "NativeConnectorSwipe",
    "NativeReportDocumentIcon",
    "NativeConnectorPagesSection",
    "NativeConnectorExpandedReport",
    "NativeReportsView",
    "NativeEvidencePresentation",
    "NativeSetupView",
  ]) {
    assert.match(nativeUI, new RegExp(`struct ${surface}`));
  }

  assert.match(nativeUI, /\.frame\(width: 320, height: 470\.588235\)/);
  assert.match(nativeUI, /ForEach\(0\.\.<46/);
  assert.match(nativeUI, /NativeSharePill\(label: "My Page · Identity ↗", emphasized: true\)/);
  assert.match(nativeUI, /let panelWidth = min\(1120, max\(0, proxy\.size\.width - 36\)\)/);
  assert.match(nativeUI, /let contentWidth = min\(820, max\(0, panelWidth - 76\)\)/);
  assert.match(nativeUI, /NativeIdentityColumnsLayout\(spacing: 58\)/);
  assert.match(nativeUI, /Text\("ROOT · 本周写下的一句话"\)/);
  assert.match(nativeUI, /state\.openFactShare\([\s\S]*?kind: dayShareKind/);

  for (const detail of [
    "Swipe your card",
    "PERSONAL MODEL · MODEL PASS",
    "让更多 Agent 戴上这张卡",
    "AGENTS WEARING IT",
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
    "你的记忆，不用你记",
    "空白日期不做推断",
    "monthLabels",
    "zoomToMonth",
    "今天写进 Personal Model",
    "值得回去的瞬间",
    "每件事只出现一次 · 点一下回到画面",
    "FACE · 面",
    "VOLUME · 体",
    "ROOT · 根",
    "当天没有可用的画面",
    "0 / 0",
    "api/model/rewind/frames",
    "api/model/rewind/frame",
    "loadRewindFrameImage",
    "nativeNearestFrameIndex",
    "frame.time, frame.app, frame.title",
    "Persome · 已连接",
    "正在记录 · 暂停 1 小时",
    "ROOT · 今天留下的一句",
    "TOMORROW · A QUIET PROJECTION",
    "它们不是安排。明天到来时，现实会把这些影子重新写一遍。",
    "ROOT · 我是谁",
    "← → 巡星",
    "亮星可点 · ← → 巡星 · 点星座名回到那几天",
    "SAME MODEL · PRIVATE INSIDE / PUBLIC OUTSIDE",
    "划线分享",
    "打开 Evidence",
    "IT KNOWS ME",
    "保存图片",
    "已存 · 去发吧",
    "Agent 第一次戴上你的卡并完成工作后，会在这里留下一页。",
    "RESULTS OUTSIDE · EVIDENCE INSIDE",
    "CURRENT UNDERSTANDING",
  ]) {
    assert.match(nativeUI, new RegExp(detail));
  }
  assert.match(
    nativeUI,
    /NativeYearHeatmap\([\s\S]*?zoomToMonth: \{ screen = \.month \}/,
  );
  assert.doesNotMatch(nativeUI, /monthLabel\(for:/);
  assert.doesNotMatch(nativeUI, /WKWebView|WebKit/);
  assert.match(nativeUI, /state\.isMemorySkyOpen[\s\S]*accessibilityHidden/);
  assert.match(nativeUI, /onExitCommand/);
  assert.match(nativeUI, /state\.rewindDayRequest = nil/);
  assert.match(nativeUI, /Button\("✦ 证据"\) \{ state\.openEvidenceSky\(reference\) \}/);
  assert.match(nativeUI, /accessibilityLabel\("打开 Evidence · \\\(reference\)"\)/);
  assert.match(nativeUI, /accessibilityLabel\("回到当天 · \\\(reference\)"\)/);
  assert.match(nativeUI, /memorySkyEvidenceRequest/);
  assert.match(nativeUI, /nativeEvidenceSeed/);
  assert.match(nativeUI, /private var reportFaceReferences: \[String\]/);
  assert.match(nativeUI, /let prefix = "\\\(snapshot\.model\.id\):face:"/);
  assert.match(nativeUI, /primaryFaceReference\(for: theme\)/);
  assert.match(nativeUI, /let preservesFaceEvidence = index == 0 && faceReference != nil/);
  assert.match(nativeUI, /candidates\.first\(where: \{ \$0\.reference == reference \}\)/);
  assert.match(nativeUI, /share-fact-evidence:/);
  assert.match(nativeUI, /Button\("分享 ↗"\) \{ openFactShare\(star\) \}/);
  assert.match(nativeUI, /saveShareFactImage/);
  assert.match(nativeUI, /\.downloadsDirectory/);
  assert.match(nativeUI, /WhoAmI-\\\(formatter\.string\(from: Date\(\)\)\)/);
  assert.match(nativeUI, /whoAmIVisualQAPresentation == "report-expanded"/);
  assert.match(nativeUI, /frame\(height: 54\.5234375\)/);
  assert.match(nativeUI, /frame\(height: 64\.921875, alignment: \.leading\)/);
  assert.match(nativeUI, /frame\(height: 51\.546875, alignment: \.leading\)/);
  assert.match(nativeUI, /frame\(height: 48\.5\)/);
  assert.match(nativeUI, /nativeMonthName\(referenceDate\)/);
  assert.match(nativeUI, /nativeDayLetterParts/);
  assert.doesNotMatch(
    nativeUI,
    /LazyVStack\(spacing: 0, pinnedViews: \[\.sectionHeaders\]\)/,
  );
  assert.match(
    nativeUI,
    /NativeRewindDayBar\([\s\S]*?VStack\(alignment: \.leading, spacing: 0\)/,
  );
  assert.match(nativeUI, /NativeFlowTrailingKey/);
  assert.match(nativeUI, /let weekCount = 28/);
  assert.match(nativeUI, /frame\(width: 430, height: 430 \/ 1\.586\)/);
  assert.match(nativeUI, /\(28, 40, 16, 34\)/);
  assert.match(nativeUI, /\(66, 56, 14, 26\)/);
  assert.match(nativeUI, /\(46, 72, 11, 18\)/);
  assert.match(nativeUI, /\(76, 26, 9, 12\)/);
  assert.doesNotMatch(nativeUI, /COPY CARD/);
});
