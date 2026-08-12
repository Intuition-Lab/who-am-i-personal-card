import { useEffect, useMemo, useState } from "react";

import { Tabs, TabsList, TabsPanel, TabsTab } from "@/components/ui/tabs";
import type { PersonalModelSnapshot } from "@/lib/api";

type SettingsTab = "data" | "ai" | "model" | "export";

type SettingsViewProps = {
  snapshot: PersonalModelSnapshot | null;
  onBack: () => void;
  onNavigate: (route: string) => void;
  onToast: (message: string) => void;
};

const sourceCopy = {
  screenActivity: ["Screen activity", "App + window titles · private apps excluded"],
  obsidian: ["Obsidian", "Local vaults · read-only · no upload"],
  appleApps: ["Apple Notes · Calendar · Mail", "Separate, read-only scopes"],
} as const;

export function SettingsView({ snapshot, onBack, onNavigate, onToast }: SettingsViewProps) {
  const [tab, setTab] = useState<SettingsTab>("data");
  const [sources, setSources] = useState<Record<string, boolean>>({ screenActivity: true, obsidian: true, appleApps: false });
  const [permissions, setPermissions] = useState<Record<string, string>>({});

  useEffect(() => {
    void window.persomeDesktop?.getPreferences().then((value) => {
      setSources(value.sources);
      setPermissions(value.permissions);
    });
  }, []);

  const connected = useMemo(() => (snapshot?.connectors ?? []).filter((item) => item.status === "connected"), [snapshot]);

  async function toggleSource(source: string) {
    const next = !sources[source];
    setSources((current) => ({ ...current, [source]: next }));
    try {
      await window.persomeDesktop?.setSourceEnabled(source, next);
      onToast(next ? "Source enabled" : "Source paused · the gap stays visible");
    } catch (error) {
      setSources((current) => ({ ...current, [source]: !next }));
      onToast(error instanceof Error ? error.message : "Source preference was not saved.");
    }
  }

  async function exportSnapshot(format: "markdown" | "json") {
    if (!snapshot) return;
    const result = await window.persomeDesktop?.exportSnapshot(format, snapshot);
    if (result && !result.canceled) onToast("Export saved locally");
  }

  return (
    <section aria-label="Trust settings" className="screen settings active">
      <header className="context-head"><button className="back-card" onClick={onBack} type="button">Back to Card</button><span className="context-title">Trust · what comes in, who reads it</span><span /></header>
      <Tabs onValueChange={(value) => setTab(value as SettingsTab)} value={tab}>
        <TabsList className="settings-tabs">
          <TabsTab className={`settings-tab${tab === "data" ? " active" : ""}`} value="data">Data & permissions</TabsTab>
          <TabsTab className={`settings-tab${tab === "ai" ? " active" : ""}`} value="ai">Connected AI</TabsTab>
          <TabsTab className={`settings-tab${tab === "model" ? " active" : ""}`} value="model">Model</TabsTab>
          <TabsTab className={`settings-tab${tab === "export" ? " active" : ""}`} value="export">Export</TabsTab>
        </TabsList>

        <TabsPanel className={`settings-pane${tab === "data" ? " active" : ""}`} value="data">
          <h1>What Persome can see</h1><p>Pause anything. Gaps stay gaps; Persome never invents what it could not observe.</p>
          <div className="trust-label">ON THIS MAC</div>
          <div className="trust-list">
            {(Object.keys(sourceCopy) as Array<keyof typeof sourceCopy>).map((source) => (
              <div className="trust-row" key={source}><div><strong>{sourceCopy[source][0]}</strong><small>{sourceCopy[source][1]}</small></div><button aria-label={`Toggle ${sourceCopy[source][0]}`} aria-pressed={!!sources[source]} className={`toggle${sources[source] ? " on" : ""}`} onClick={() => void toggleSource(source)} type="button" /></div>
            ))}
          </div>
          <div className="trust-label">MACOS PERMISSIONS</div>
          <div className="trust-list">
            <div className="trust-row"><div><strong>Screen Recording</strong><small>{permissions.screen || "Open System Settings to confirm"} · needed only for visual Rewind</small></div><button className="row-button" onClick={() => void window.persomeDesktop?.openSystemPermission("screen")} type="button">Open Settings</button></div>
            <div className="trust-row"><div><strong>Microphone</strong><small>{permissions.microphone || "not requested"} · local transcription only</small></div><button className="row-button" onClick={() => void window.persomeDesktop?.openSystemPermission("microphone")} type="button">Open Settings</button></div>
          </div>
          <div className="local-note"><span>Everything stays on this Mac. Nothing leaves without a grant you made.</span><code>local-only</code></div>
        </TabsPanel>

        <TabsPanel className={`settings-pane${tab === "ai" ? " active" : ""}`} value="ai">
          <h1>Who wears your card</h1><p>Every AI gets a separate grant, scope, session, and revoke control.</p>
          <div className="trust-list">
            {(snapshot?.connectors ?? []).map((connector) => <div className="trust-row" key={connector.id}><div><strong>{connector.name}</strong><small>{connector.status === "connected" ? "identity · recall · evidence — local grant active" : "Not connected"}</small></div><button className="row-button" onClick={() => onNavigate("swipe")} type="button">{connector.status === "connected" ? "Review access" : "Swipe card"}</button></div>)}
            {!snapshot?.connectors.length && <div className="trust-row"><div><strong>No AI connected</strong><small>Persome is waiting for a supported MCP client.</small></div><button className="row-button" onClick={() => onNavigate("swipe")} type="button">Open Swipe</button></div>}
          </div>
          <div className="local-note"><span>{connected.length} AI {connected.length === 1 ? "has" : "have"} an active local grant.</span><code>{connected.length ? "scoped" : "private"}</code></div>
        </TabsPanel>

        <TabsPanel className={`settings-pane${tab === "model" ? " active" : ""}`} value="model">
          <h1>What the model understands</h1><p>Review and correct. Every change stays attributable to you.</p>
          <div className="trust-list">
            <div className="trust-row"><div><strong>Root</strong><small>{snapshot?.personalModel.root || "Still forming"}</small></div><button className="row-button" onClick={() => onNavigate("map:living")} type="button">Open</button></div>
            {(snapshot?.personalModel.faces ?? []).slice(0, 4).map((face) => <div className="trust-row" key={face.id}><div><strong>{face.text}</strong><small>{face.observations} observations · {Math.round(face.confidence * 100)}% confidence</small></div><button className="row-button" onClick={() => onNavigate("home:ask")} type="button">Correct</button></div>)}
          </div>
        </TabsPanel>

        <TabsPanel className={`settings-pane${tab === "export" ? " active" : ""}`} value="export">
          <h1>Take all of it with you</h1><p>Choose a local destination. Persome does not upload an export.</p>
          <div className="trust-list">
            <div className="trust-row"><div><strong>Readable model</strong><small>Markdown · identity, patterns, days and evidence references</small></div><button className="row-button" disabled={!snapshot} onClick={() => void exportSnapshot("markdown")} type="button">Export</button></div>
            <div className="trust-row"><div><strong>Current snapshot</strong><small>JSON · the authorized product snapshot shown in this App</small></div><button className="row-button" disabled={!snapshot} onClick={() => void exportSnapshot("json")} type="button">Export</button></div>
          </div>
        </TabsPanel>
      </Tabs>
    </section>
  );
}
