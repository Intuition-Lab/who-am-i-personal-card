import { type FormEvent, useEffect, useState } from "react";

import { launchModelSetup, saveProfile, setupStatus } from "@/lib/api";

type SetupViewProps = {
  message: string | null;
  onReady: () => Promise<unknown>;
  onToast: (message: string) => void;
};

type SetupState = Awaited<ReturnType<typeof setupStatus>> | null;

export function SetupView({ message, onReady, onToast }: SetupViewProps) {
  const [status, setStatus] = useState<SetupState>(null);
  const [displayName, setDisplayName] = useState("");
  const [handle, setHandle] = useState("");
  const [busy, setBusy] = useState(false);

  async function refresh() {
    try {
      const next = await setupStatus();
      setStatus(next);
      if (next.ready) await onReady();
    } catch (error) {
      onToast(error instanceof Error ? error.message : "Setup status is unavailable.");
    }
  }

  useEffect(() => {
    void refresh();
    const timer = window.setInterval(() => void refresh(), 2500);
    return () => window.clearInterval(timer);
  }, []);

  async function createCard(event: FormEvent) {
    event.preventDefault();
    if (!displayName.trim() || !handle.trim()) return;
    setBusy(true);
    try {
      await saveProfile({
        displayName: displayName.trim(),
        handle: handle.trim().replace(/^@?/, "@"),
        tagline: "My Personal Model, as of now.",
        description: "A living model formed from my own memory and activity.",
      });
      onToast("Your Personal Card is now yours");
      await refresh();
    } catch (error) {
      onToast(error instanceof Error ? error.message : "Your card could not be created.");
    } finally {
      setBusy(false);
    }
  }

  async function openSetup() {
    setBusy(true);
    try {
      await launchModelSetup();
      onToast("Personal Model setup opened");
    } catch (error) {
      onToast(error instanceof Error ? error.message : "Setup could not be opened.");
    } finally {
      setBusy(false);
    }
  }

  const state = status?.state;
  return (
    <section className="screen setup-screen active">
      <article className="setup-card">
        <span className="living-kicker">PERSOME · PRIVATE BETA</span>
        <h1>{state === "profile_required" || !state ? "Make this Personal Model yours" : "Finish your Personal Model"}</h1>
        <p>{message || "Persome checks for an existing Personal Model first. If none exists, the bundled setup initializes one on this Mac."}</p>
        {(state === "profile_required" || !state) && (
          <form className="setup-form" onSubmit={(event) => void createCard(event)}>
            <label><span>Your name</span><input autoFocus onChange={(event) => setDisplayName(event.target.value)} placeholder="How your card should address you" value={displayName} /></label>
            <label><span>Your handle</span><input onChange={(event) => setHandle(event.target.value)} placeholder="@you" value={handle} /></label>
            <button className="primary" disabled={busy || !displayName.trim() || !handle.trim()} type="submit">{busy ? "Creating…" : "Create my Personal Card"}</button>
          </form>
        )}
        {state === "not_installed" && <button className="primary setup-action" disabled={busy} onClick={() => void openSetup()} type="button">Install the bundled Personal Model</button>}
        {state === "onboarding_required" && <button className="primary setup-action" disabled={busy} onClick={() => void openSetup()} type="button">Open permissions & finish setup</button>}
        <footer><span>{status?.personalModel.connection || "checking"}</span><span>Nothing here loads another owner's card.</span></footer>
      </article>
    </section>
  );
}
