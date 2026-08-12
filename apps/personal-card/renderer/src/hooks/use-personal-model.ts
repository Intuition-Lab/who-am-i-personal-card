import { useCallback, useEffect, useState } from "react";

import { type PersonalModelSnapshot, PersomeApiError } from "@/lib/api";
import { activeModelStore } from "@/lib/model-store";

export type ModelLoadState = {
  phase: "loading" | "ready" | "setup" | "error";
  modelId: string | null;
  revision: number;
  snapshot: PersonalModelSnapshot | null;
  message: string | null;
};

const initialState: ModelLoadState = {
  phase: "loading",
  modelId: null,
  revision: 0,
  snapshot: null,
  message: null,
};

export function usePersonalModel() {
  const [state, setState] = useState<ModelLoadState>(initialState);

  const refresh = useCallback(async () => {
    setState((current) => ({ ...current, phase: "loading", message: null }));
    try {
      const payload = await activeModelStore.bootstrap();
      const snapshot = payload.snapshot as PersonalModelSnapshot;
      if (snapshot.model.id !== payload.activeModelId) {
        throw new PersomeApiError("Personal Model response did not match its owner.");
      }
      setState({
        phase: "ready",
        modelId: payload.activeModelId,
        revision: payload.revision,
        snapshot,
        message: null,
      });
    } catch (error) {
      const candidate = error as { message?: string; code?: string; status?: number };
      const safe = error instanceof PersomeApiError
        ? error
        : candidate?.code
          ? new PersomeApiError(
              candidate.message || "Persome could not load your Personal Model.",
              candidate.code,
              candidate.status,
            )
          : new PersomeApiError("Persome could not load your Personal Model.");
      const setup = ["PROFILE_REQUIRED", "RUNTIME_NOT_INSTALLED", "RUNTIME_ONBOARDING_REQUIRED"]
        .includes(safe.code);
      setState({
        ...initialState,
        phase: setup ? "setup" : "error",
        message: safe.message,
      });
    }
  }, []);

  useEffect(() => {
    return activeModelStore.subscribe((next) => {
      if (next.phase === "ready" && next.snapshot && next.activeModelId) {
        setState({
          phase: "ready",
          modelId: next.activeModelId,
          revision: next.revision,
          snapshot: next.snapshot as PersonalModelSnapshot,
          message: null,
        });
      }
    });
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  return { ...state, refresh };
}
