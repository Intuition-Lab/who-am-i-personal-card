import "../../../src/client/active-model-store.js";

export type ActiveModelStoreState = {
  activeModelId: string | null;
  snapshot: unknown;
  revision: number;
  loadingModelId: string | null;
  switchError: string | null;
  phase: "idle" | "switching" | "ready" | "error";
};

type Store = {
  getState(): ActiveModelStoreState;
  subscribe(listener: (state: ActiveModelStoreState) => void): () => void;
  bootstrap(options?: { modelId?: string }): Promise<ActiveModelStoreState>;
  request<T>(path: string, options?: Record<string, unknown>): Promise<T>;
};

declare global {
  interface Window {
    ActivePersonalModelStore: new (options?: Record<string, unknown>) => Store;
  }
}

export const activeModelStore = new window.ActivePersonalModelStore();
