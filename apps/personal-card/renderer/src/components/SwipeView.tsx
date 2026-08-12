import { useEffect, useMemo, useState } from "react";

import { Sky } from "@/components/Sky";
import {
  connectAgent,
  listAgentReports,
  revokeAgent,
  type AgentReport,
  type PersonalModelSnapshot,
} from "@/lib/api";

type SwipeViewProps = {
  snapshot: PersonalModelSnapshot | null;
  onBack: () => void;
  onToast: (message: string) => void;
  onModelChanged: () => Promise<unknown>;
};

type Overlay = "scope" | "report" | null;

export function SwipeView({ snapshot, onBack, onToast, onModelChanged }: SwipeViewProps) {
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [swiping, setSwiping] = useState(false);
  const [overlay, setOverlay] = useState<Overlay>(null);
  const [reports, setReports] = useState<AgentReport[]>(snapshot?.reports ?? []);
  const [busy, setBusy] = useState(false);
  const [revokedIds, setRevokedIds] = useState<Set<string>>(() => new Set());
  const connectors = (snapshot?.connectors ?? []).map((connector) =>
    revokedIds.has(connector.id) ? { ...connector, status: "available" as const } : connector
  );
  const selected = connectors.find((connector) => connector.id === selectedId) ?? null;

  useEffect(() => {
    setReports(snapshot?.reports ?? []);
  }, [snapshot]);

  useEffect(() => {
    void listAgentReports().then((payload) => setReports(payload.reports)).catch(() => undefined);
  }, []);

  const activeReport = useMemo(() => {
    if (selectedId) {
      const selectedReport = reports.find((report) => report.connectorId === selectedId);
      if (selectedReport) return selectedReport;
    }
    return reports[0] ?? null;
  }, [reports, selectedId]);

  async function confirmSwipe() {
    if (!selected || busy) return;
    setBusy(true);
    setOverlay(null);
    setSwiping(true);
    try {
      await connectAgent(selected.id);
      await onModelChanged();
      const payload = await listAgentReports();
      setReports(payload.reports);
      onToast("Grant verified · receipt saved");
    } catch (error) {
      onToast(error instanceof Error ? error.message : "This AI could not verify the grant.");
    } finally {
      window.setTimeout(() => setSwiping(false), 240);
      setBusy(false);
    }
  }

  async function revokeSelected() {
    if (!selected || busy) return;
    setBusy(true);
    try {
      await revokeAgent(selected.id);
      setRevokedIds((current) => new Set(current).add(selected.id));
      setOverlay(null);
      await onModelChanged();
      onToast(`${selected.name} access revoked`);
    } catch (error) {
      onToast(error instanceof Error ? error.message : "This access could not be revoked.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section aria-label="Swipe Your Card" className="screen swipe-screen active">
      <header className="swipe-head">
        <button className="back-card" onClick={onBack} type="button">Back to Card</button>
        <div><div className="swipe-copy">SWIPE YOUR CARD</div><h1>Same you, every AI</h1></div>
        <span className="swipe-copy">MCP · LOCAL GRANTS</span>
      </header>
      <div className="swipe-body">
        <div className="swipe-stage">
          <div className="swipe-card-zone">
            <article className={`swipe-card${swiping ? " swiping" : ""}`}>
              <Sky className="sky-canvas" colors="767e8b,c6cdd7,ebe4d2" glow={0.18} glowPosition={[0.72, 0.16]} speed={0.52} />
              <div className="card-top micro"><span>№ {snapshot?.model.memberNumber || "—"}</span><span>Personal Card</span></div>
              <div className="card-bottom"><span className="card-handle">{snapshot?.model.handle || "@you"}</span><span className="card-right">PERSOME<br />ONE OF ONE</span></div>
            </article>
            <div className="reader"><div><div className="reader-slot" /><p>READER</p><span><i className="reader-dot" />{swiping ? "VERIFYING LOCALLY" : "READY TO SWIPE"}</span></div></div>
          </div>
          <div className="agent-rail">
            <div className="agent-list">
              {connectors.map((connector) => (
                <button
                  className={`agent${connector.status === "connected" ? " connected" : ""}${selectedId === connector.id ? " selected" : ""}`}
                  key={connector.id}
                  onClick={() => setSelectedId(connector.id)}
                  type="button"
                >
                  <strong>{connector.name || connector.product}</strong>
                  <span>{connector.status === "connected" ? "WEARING YOUR CARD · REPORTS AVAILABLE" : "READY TO SWIPE"}</span>
                </button>
              ))}
              {!connectors.length && <div className="empty-note">No MCP client has been discovered on this Mac yet.</div>}
            </div>
            <button className="agent-report-card" disabled={!activeReport} onClick={() => setOverlay("report")} type="button">
              <small>LATEST AGENT REPORT{activeReport ? ` · ${activeReport.connectorId.toUpperCase()}` : ""}</small>
              <strong>{activeReport?.title || "Reports appear after an AI reads your card"}</strong>
              <p>{activeReport ? `${activeReport.readCount} reads · ${activeReport.evidenceCount} evidence` : "No synthetic report is generated from connection alone"}</p>
              <span>{activeReport ? "Read full report →" : "Waiting for real activity"}</span>
            </button>
          </div>
        </div>
        <footer className="swipe-footer">
          <span className="swipe-status">{selected ? (selected.status === "connected" ? "Connected · review or renew this AI's scope" : "Ready · a local grant will be created after approval") : "Choose an AI. Each one receives its own scope and receipt."}</span>
          <button className="swipe-button" disabled={!selected || busy} onClick={() => setOverlay("scope")} type="button">{selected ? (selected.status === "connected" ? "Review access" : `Swipe to ${selected.name}`) : "Choose an AI"}</button>
        </footer>
      </div>

      <button aria-label="Close dialog" className={`sheet-backdrop${overlay ? " open" : ""}`} onClick={() => setOverlay(null)} type="button" />
      <aside aria-modal="true" className={`sheet scope-sheet${overlay === "scope" ? " open" : ""}`} role="dialog">
        <div className="sheet-head"><span>LOCAL GRANT · SEPARATE RECEIPT</span><button className="sheet-close" onClick={() => setOverlay(null)} type="button">×</button></div>
        <h2>Let {selected?.name || "this AI"} wear your card?</h2>
        <p>Only the selected scopes leave Persome. Raw captures and the complete model stay on this Mac.</p>
        <div className="scope-row"><span>Identity</span><strong>Read</strong></div>
        <div className="scope-row"><span>Recall</span><strong>Ask</strong></div>
        <div className="scope-row"><span>Evidence</span><strong>Linked results only</strong></div>
        <div className="scope-actions"><button className="secondary" onClick={() => setOverlay(null)} type="button">Cancel</button>{selected?.status === "connected" && <button className="secondary" disabled={busy} onClick={() => void revokeSelected()} type="button">Revoke access</button>}<button className="primary" disabled={busy} onClick={() => void confirmSwipe()} type="button">{busy ? "Verifying…" : selected?.status === "connected" ? "Renew local grant" : "Create local grant"}</button></div>
      </aside>
      <aside aria-modal="true" className={`sheet report-sheet${overlay === "report" ? " open" : ""}`} role="dialog">
        <div className="sheet-head"><span>AGENT REPORT · REAL ACTIVITY ONLY</span><button className="sheet-close" onClick={() => setOverlay(null)} type="button">×</button></div>
        <h2>{activeReport?.title || "No report yet"}</h2>
        <p>{activeReport?.summary || "Connecting an AI does not create a report. A report appears only after observable agent activity."}</p>
        <div className="report-stats"><div className="report-stat"><strong>{activeReport?.readCount ?? 0}</strong><span>READS</span></div><div className="report-stat"><strong>{activeReport?.evidenceCount ?? 0}</strong><span>EVIDENCE</span></div></div>
        <ul className="report-list">{(activeReport?.sections ?? []).map((section, index) => <li key={`${section.kind}-${index}`}><strong>{section.title}</strong> · {section.body}</li>)}</ul>
        <div className="report-actions"><button className="primary" onClick={() => setOverlay(null)} type="button">Done</button></div>
      </aside>
    </section>
  );
}
