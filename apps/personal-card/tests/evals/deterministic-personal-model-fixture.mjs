const TERM_GROUPS = Object.freeze([
  ["all", "everything", "complete", "完整", "完整的", "全部"],
  ["beta", "test", "内测"],
  ["launch", "release", "ship", "rollout", "发布", "上线"],
  ["schedule", "when", "什么时候", "time"],
  ["owner", "owns", "负责", "负责人"],
  ["risk", "permission", "风险", "权限"],
  ["privacy", "private", "keep", "隐私"],
  ["storage", "local", "computer", "notes", "本机", "本地"],
  ["decision", "docs", "documents", "决定", "决策"],
  ["writing", "written", "write", "写"],
  ["preference", "prefer", "style", "偏好"],
  ["review", "meeting", "评审", "会议"],
  ["budget", "finance", "预算", "财务"],
]);

const TERM_CANONICAL = new Map(
  TERM_GROUPS.flatMap((group) => group.map((term) => [term, group[0]])),
);

function terms(value) {
  const source = String(value || "").toLocaleLowerCase();
  const normalized = source
      .toLocaleLowerCase()
      .replace(/[^\p{L}\p{N}]+/gu, " ")
      .trim()
      .split(/\s+/u)
      .filter(Boolean)
      .map((term) => TERM_CANONICAL.get(term) ?? term);
  for (const group of TERM_GROUPS) {
    if (group.some((term) => /[^\x00-\x7f]/u.test(term) && source.includes(term))) {
      normalized.push(group[0]);
    }
  }
  return new Set(normalized);
}

function cloneModel(model) {
  return structuredClone(model);
}

export class DeterministicPersonalModelFixture {
  constructor(models) {
    this.models = new Map(
      Object.entries(models).map(([modelId, model]) => [
        modelId,
        cloneModel(model),
      ]),
    );
    this.revisions = new Map([...this.models.keys()].map((id) => [id, 1]));
  }

  model(modelId) {
    const model = this.models.get(modelId);
    if (!model) throw Object.assign(new Error("Model not found."), {
      code: "MODEL_NOT_FOUND",
    });
    return model;
  }

  search(modelId, query) {
    const model = this.model(modelId);
    const queryTerms = terms(query);
    const wantsComplete = queryTerms.has("all");
    const scored = model.memories.map((memory) => {
      const memoryTerms = new Set(memory.keywords.map(
        (term) => TERM_CANONICAL.get(term) ?? term,
      ));
      const overlap = [...queryTerms].filter((term) => memoryTerms.has(term));
      if (wantsComplete && queryTerms.has("launch")) {
        return { memory, score: memory.topic === "launch" ? 100 : 0 };
      }
      return { memory, score: overlap.length };
    });
    const maximumScore = Math.max(0, ...scored.map(({ score }) => score));
    const minimumScore = Math.min(2, queryTerms.size);
    const matches = scored
      .filter(({ score }) => score === maximumScore && score >= minimumScore)
      .map(({ memory }) => memory);
    return structuredClone(matches.map((memory) => ({
      modelId,
      id: memory.id,
      text: memory.text,
      evidenceRef: memory.evidenceRef,
    })));
  }

  ask(modelId, query) {
    const results = this.search(modelId, query);
    if (results.length === 0) {
      return {
        modelId,
        refused: true,
        answer: "The Personal Model does not have enough recorded evidence to answer.",
        evidenceRefs: [],
      };
    }
    return {
      modelId,
      refused: false,
      answer: results.map(({ text }) => text).join(" "),
      evidenceRefs: results.map(({ evidenceRef }) => evidenceRef),
    };
  }

  evidence(modelId, reference) {
    if (!String(reference).startsWith(`${modelId}:`)) {
      throw Object.assign(new Error("Evidence belongs to another model."), {
        code: "EVIDENCE_MODEL_MISMATCH",
      });
    }
    const model = this.model(modelId);
    const memory = model.memories.find(
      ({ evidenceRef }) => evidenceRef === reference,
    );
    const event = model.rewind.find(
      ({ evidenceRef }) => evidenceRef === reference,
    );
    const source = memory ?? event;
    if (!source) throw Object.assign(new Error("Evidence not found."), {
      code: "EVIDENCE_NOT_FOUND",
    });
    return structuredClone({ modelId, reference, content: source });
  }

  correct(modelId, memoryId, replacementText) {
    const model = this.model(modelId);
    const memory = model.memories.find(({ id }) => id === memoryId);
    if (!memory) throw Object.assign(new Error("Memory not found."), {
      code: "MEMORY_NOT_FOUND",
    });
    memory.text = replacementText;
    const revision = this.revisions.get(modelId) + 1;
    this.revisions.set(modelId, revision);
    return { modelId, memoryId, revision };
  }

  rewind(modelId, from, to) {
    const start = new Date(from).getTime();
    const end = new Date(to).getTime();
    return structuredClone(this.model(modelId).rewind.filter((event) =>
      new Date(event.startedAt).getTime() >= start &&
      new Date(event.endedAt).getTime() <= end
    ));
  }
}
