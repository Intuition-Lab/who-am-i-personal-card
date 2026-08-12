import { activeModelStore } from "@/lib/model-store";

export type PersonalModelSnapshot = {
  schemaVersion: string;
  model: {
    id: string;
    displayName: string;
    handle: string;
    memberNumber: string;
    sinceYear: number;
    status: "online" | "offline" | "snapshot";
  };
  card: {
    monthYear: string;
    tagline: string;
    publicUrl: string;
    material?: string;
    glyph: boolean[];
  };
  personalModel: {
    memoryCount: number;
    root: string;
    updatedAt: string;
    faces: Array<{
      id: string;
      text: string;
      observations: number;
      confidence: number;
      evidenceRefs?: string[];
    }>;
  };
  now: {
    items: Array<{
      id: string;
      kind: "past" | "present" | "future";
      title: string;
      why: string;
      when: string;
      dayId?: string;
    }>;
  };
  time: {
    days: Array<{
      id: string;
      title: string;
      portrait: string;
      letter?: string;
      events: Array<{
        id: string;
        time: string;
        title: string;
        detail: string;
        app?: string;
        evidenceRef?: string;
      }>;
    }>;
  };
  identity: {
    description: string;
    dailyLine: string;
    weeklyLetter: string[];
  };
  connectors: Array<{
    id: string;
    name: string;
    product: string;
    status: "connected" | "available" | "missing" | "connecting";
    iconUrl?: string;
    sessionId?: string;
  }>;
  reports: AgentReport[];
};

export type AgentReport = {
  id: string;
  modelId: string;
  connectorId: string;
  title: string;
  summary: string;
  updatedAt: string;
  readCount: number;
  evidenceCount: number;
  sections: Array<{ kind: string; title: string; body: string }>;
  evidenceRefs: string[];
};

type ApiErrorPayload = {
  code?: string;
  error?: string;
  message?: string;
};

export class PersomeApiError extends Error {
  code: string;
  status: number;

  constructor(message: string, code = "PERSOME_API_ERROR", status = 0) {
    super(message);
    this.name = "PersomeApiError";
    this.code = code;
    this.status = status;
  }
}

export async function apiJson<T>(
  path: string,
  options: Omit<RequestInit, "body"> & { body?: unknown } = {},
): Promise<T> {
  const response = await fetch(path, {
    ...options,
    credentials: "same-origin",
    headers: {
      Accept: "application/json",
      ...(options.body == null ? {} : { "Content-Type": "application/json" }),
      ...options.headers,
    },
    body: options.body == null
      ? undefined
      : typeof options.body === "string"
        ? options.body
        : JSON.stringify(options.body),
  });
  const payload = await response.json().catch(() => ({})) as ApiErrorPayload & T;
  if (!response.ok || (payload as { ok?: boolean }).ok === false) {
    throw new PersomeApiError(
      payload.error || payload.message || "Persome is unavailable.",
      payload.code,
      response.status,
    );
  }
  return payload;
}

export async function bootstrapModel(): Promise<{
  modelId: string;
  revision: number;
  snapshot: PersonalModelSnapshot;
}> {
  return apiJson("/api/model/bootstrap");
}

export async function askModel(question: string) {
  return activeModelStore.request<{
    ok: true;
    modelId: string;
    revision: number;
    answer: string;
    results: Array<{ title?: string; text?: string; reference?: string }>;
  }>("/api/model/ask", { method: "POST", body: { question } });
}

export async function correctModel(correction: string) {
  return apiJson<{
    ok: true;
    modelId: string;
    revision: number;
    result: unknown;
  }>("/api/model/correct", { method: "POST", body: { correction } });
}

export async function jotModel(text: string) {
  return apiJson<{
    ok: true;
    modelId: string;
    revision: number;
    receipt?: string;
  }>("/api/model/jot", { method: "POST", body: { text } });
}

export async function connectAgent(connectorId: string) {
  return activeModelStore.request<{
    ok: true;
    modelId: string;
    revision: number;
    connector: PersonalModelSnapshot["connectors"][number];
  }>(`/api/model/connectors/${encodeURIComponent(connectorId)}/connect`, {
    method: "POST",
    body: {},
  });
}

export async function revokeAgent(connectorId: string) {
  return apiJson<{
    ok: true;
    modelId: string;
    revision: number;
    connectorId: string;
    revoked: boolean;
  }>(`/api/model/connectors/${encodeURIComponent(connectorId)}/revoke`, {
    method: "POST",
    body: {},
  });
}

export async function listAgentReports() {
  return activeModelStore.request<{
    ok: true;
    modelId: string;
    revision: number;
    reports: AgentReport[];
    events: Array<{ id?: string; summary?: string; createdAt?: string }>;
  }>("/api/model/reports");
}

export async function setupStatus() {
  return apiJson<{
    ok: true;
    ready: boolean;
    state: "ready" | "profile_required" | "not_installed" | "onboarding_required";
    profile: null | { displayName: string; handle: string };
    personalModel: {
      installed: boolean;
      initialized: boolean;
      buildStatus: string;
      connection: string;
    };
  }>("/api/setup/status");
}

export async function saveProfile(profile: {
  displayName: string;
  handle: string;
  tagline?: string;
  description?: string;
}) {
  return apiJson<{ ok: true; state: string }>("/api/setup/profile", {
    method: "POST",
    body: profile,
  });
}

export async function launchModelSetup() {
  return apiJson<{ ok: true; launched: boolean; state: string }>(
    "/api/setup/personal-model",
    { method: "POST", body: {} },
  );
}
