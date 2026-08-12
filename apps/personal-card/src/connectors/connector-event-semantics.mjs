const CONNECTOR_NAMES = Object.freeze({
  codex: "Codex",
  "claude-code": "Claude Code",
});

const READ_CONTEXT_BY_TOOL = Object.freeze({
  behavior_patterns: "行为模式",
  current_context: "当前模型上下文",
  entity_graph: "人物与关系",
  get_pending_model_work: "待沉淀记录",
  list_memories: "记忆目录",
  read_memory: "记忆内容",
  read_receipt: "证据回执",
  recent_activity: "最近活动",
  resolve_evidence: "证据内容",
  search: "记忆搜索结果",
  search_captures: "屏幕回看记录",
  verify_fact: "事实核对依据",
});

export function connectorDisplayName(connectorId) {
  return CONNECTOR_NAMES[connectorId] ?? connectorId;
}

export function contextTypeForEvent(event) {
  if (event?.eventType !== "tools/call") return null;
  return READ_CONTEXT_BY_TOOL[event.tool] ?? null;
}

export function isContextReadEvent(event) {
  return contextTypeForEvent(event) !== null;
}

export function recordedOutcomeForEvent(event) {
  const parts = [];
  if (Array.isArray(event?.details)) {
    parts.push(...event.details.filter((detail) => detail));
  }
  if (event?.interpretation) parts.push(event.interpretation);
  return [...new Set(parts)];
}
