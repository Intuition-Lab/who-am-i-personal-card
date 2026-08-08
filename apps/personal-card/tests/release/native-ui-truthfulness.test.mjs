import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import test from "node:test";

const nativeUIPath = fileURLToPath(
  new URL("../../macos/WhoAmINativeUI.swift", import.meta.url),
);

test("native beta UI keeps new grounding fields optional and old responses compatible", async () => {
  const source = await readFile(nativeUIPath, "utf8");

  assert.match(source, /struct AskResponse: Decodable[\s\S]*let results: \[SearchResult\]\?/);
  assert.match(source, /struct AskResponse: Decodable[\s\S]*let evidenceRefs: \[String\]\?/);
  assert.match(source, /struct SearchResult: Decodable[\s\S]*let evidenceRefs: \[String\]\?/);
  assert.match(source, /let sufficientEvidence: Bool\?/);
  assert.match(source, /let contentType: String\?/);
  assert.match(source, /let timeRange: String\?/);
  assert.match(source, /let confidence: Double\?/);
});

test("search and ask expose loading, empty, failure, and insufficient-evidence states", async () => {
  const source = await readFile(nativeUIPath, "utf8");

  for (const phase of ["idle", "loading", "success", "empty", "insufficient", "failure"]) {
    assert.match(source, new RegExp(`case ${phase}`));
  }
  assert.match(source, /没有找到相关内容/);
  assert.match(source, /搜索暂时不可用/);
  assert.match(source, /这次没有回答成功/);
  assert.match(source, /Evidence 不足/);
  assert.match(source, /NativeSearchResultRow/);
  assert.match(source, /loadEvidence\(reference\)/);
});

test("native beta language separates records, inference, generated text, and suggestions", async () => {
  const source = await readFile(nativeUIPath, "utf8");

  assert.match(source, /case \.recorded: return "记录事实"/);
  assert.match(source, /case \.inference: return "Personal Model 推断"/);
  assert.match(source, /case \.generated: return "生成内容"/);
  assert.match(source, /case \.suggestion: return "延续建议"/);
  assert.match(source, /来源：/);
  assert.match(source, /置信度/);
  assert.match(source, /hasReliableSuggestionSource/);
  assert.match(source, /!item\.isFutureLike \|\| item\.hasReliableSuggestionSource/);
  assert.match(source, /item\.isFutureLike \? "SUGGEST"/);
  assert.match(source, /if !item\.isFutureLike, let when/);
});

test("native beta does not claim reports or public sharing before they exist", async () => {
  const source = await readFile(nativeUIPath, "utf8");

  assert.match(source, /var hasSubstantiveData: Bool/);
  assert.match(source, /报告尚未产生/);
  assert.match(source, /已连接，但尚未产生有实质数据的报告/);
  assert.match(source, /Button\(copied \? "已复制" : "复制卡片"\)/);
  assert.match(source, /isConfirmedPublished == true/);
  assert.doesNotMatch(source, /func shareCard\(/);
});

test("native beta covers setup, evidence, correction, keyboard, and VoiceOver states", async () => {
  const source = await readFile(nativeUIPath, "utf8");

  for (const label of [
    "第一次使用",
    "Personal Model 正在形成",
    "Personal Model 尚未授权",
    "本机服务未启动",
    "本机未安装，当前无法连接",
    "这条 Evidence 已失效",
    "更正已写入",
    "未能保存更正",
  ]) {
    assert.match(source, new RegExp(label));
  }
  assert.match(source, /keyboardShortcut\("k", modifiers: \.command\)/);
  assert.match(source, /keyboardShortcut\(\.cancelAction\)/);
  assert.match(source, /accessibilityLabel/);
  assert.match(source, /@FocusState/);
  assert.match(source, /font\(\.body\)/);
  assert.match(source, /ScrollView/);
});
