import { type CSSProperties, useEffect, useMemo, useState } from "react";

import { Sky } from "@/components/Sky";
import { Tabs, TabsList, TabsPanel, TabsTab } from "@/components/ui/tabs";
import type { PersonalModelSnapshot } from "@/lib/api";

type MapMode = "nebula" | "living" | "rewind";
type RewindMode = "day" | "week" | "month" | "year";
type SheetName = "remind" | "share" | null;

function localDateKey(date: Date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function dayDate(id: string | undefined) {
  if (!id || !/^\d{4}-\d{2}-\d{2}$/.test(id)) return null;
  const value = new Date(`${id}T12:00:00`);
  return Number.isNaN(value.getTime()) ? null : value;
}

const nodePositions = [
  [43, 51, 9],
  [24, 34, 4],
  [65, 28, 5],
  [27, 70, 4],
  [57, 68, 4],
] as const;

function ambientStars() {
  let seed = 4289;
  const random = () => {
    seed = seed * 48271 % 2147483647;
    return (seed - 1) / 2147483646;
  };
  return Array.from({ length: 68 }, () => ({
    left: 5 + random() * 84,
    top: 9 + random() * 82,
    size: 0.8 + random() * 2.1,
    opacity: 0.16 + random() * 0.46,
  }));
}

function routeState(route: string): { map: MapMode; rewind: RewindMode } {
  const parts = route.split(":");
  const map = (["nebula", "living", "rewind"].includes(parts[1]) ? parts[1] : "nebula") as MapMode;
  const rewind = (["day", "week", "month", "year"].includes(parts[2]) ? parts[2] : "day") as RewindMode;
  return { map, rewind };
}

type MapViewProps = {
  route: string;
  snapshot: PersonalModelSnapshot | null;
  onBack: () => void;
  onNavigate: (route: string) => void;
  onToast: (message: string) => void;
};

export function MapView({ route, snapshot, onBack, onNavigate, onToast }: MapViewProps) {
  const initial = routeState(route);
  const [mode, setMode] = useState<MapMode>(initial.map);
  const [rewindMode, setRewindMode] = useState<RewindMode>(initial.rewind);
  const [selectedNode, setSelectedNode] = useState(0);
  const [selectedDay, setSelectedDay] = useState(0);
  const [selectedEvent, setSelectedEvent] = useState(0);
  const [sheet, setSheet] = useState<SheetName>(null);
  const [expanded, setExpanded] = useState(false);
  const ambient = useMemo(ambientStars, []);
  const days = snapshot?.time.days ?? [];
  const dayIndex = useMemo(() => new Map(days.map((item, index) => [item.id, index])), [days]);
  const day = days[selectedDay] ?? days[0];
  const event = day?.events[selectedEvent] ?? day?.events[0];

  useEffect(() => {
    const next = routeState(route);
    setMode(next.map);
    setRewindMode(next.rewind);
  }, [route]);

  useEffect(() => {
    setSelectedDay(Math.max(0, days.length - 1));
    setSelectedEvent(0);
  }, [snapshot?.model.id]);

  const nodes = useMemo(() => {
    const root = snapshot?.personalModel.root || snapshot?.identity.dailyLine || "Your Personal Model is still forming.";
    const faces = snapshot?.personalModel.faces ?? [];
    return [
      {
        label: "ROOT",
        kind: "INFERENCE · ROOT",
        title: root,
        meta: `${snapshot?.personalModel.memoryCount ?? 0} memories · current model root`,
        confidence: 1,
      },
      ...faces.slice(0, 4).map((face, index) => ({
        label: index === 0 ? "STRONGEST FACE" : `FACE ${String(index + 1).padStart(2, "0")}`,
        kind: "LIVING MODEL · FACE",
        title: face.text,
        meta: `confidence ${face.confidence.toFixed(2)} · ${face.observations} observations`,
        confidence: face.confidence,
      })),
    ].slice(0, 5);
  }, [snapshot]);
  const activeNode = nodes[selectedNode] ?? nodes[0];

  const latestDate = dayDate(days.at(-1)?.id) ?? new Date();
  const weekDays = Array.from({ length: 7 }, (_, index) => {
    const calendarDate = new Date(latestDate);
    calendarDate.setDate(latestDate.getDate() - 6 + index);
    const sourceIndex = dayIndex.get(localDateKey(calendarDate)) ?? -1;
    const source = sourceIndex >= 0 ? days[sourceIndex] : undefined;
    const eventCount = source?.events.length ?? 0;
    return {
      sourceIndex,
      label: source?.title || calendarDate.toLocaleDateString("en-US", { weekday: "short" }),
      date: String(calendarDate.getDate()).padStart(2, "0"),
      topic: source?.events[0]?.app || source?.events[0]?.title || "Gap",
      hours: eventCount ? `${Math.max(1, eventCount)}h ${String(eventCount * 7 % 60).padStart(2, "0")}m` : "—",
      height: source ? Math.min(88, 12 + eventCount * 12) : 5,
      opacity: source ? Math.min(0.9, 0.22 + eventCount * 0.12) : 0.08,
    };
  });
  const maxEvents = Math.max(1, ...days.map((item) => item.events.length));
  const monthAnchor = latestDate;
  const monthStart = new Date(monthAnchor.getFullYear(), monthAnchor.getMonth(), 1, 12);
  const monthOffset = (monthStart.getDay() + 6) % 7;
  const monthDayCount = new Date(monthAnchor.getFullYear(), monthAnchor.getMonth() + 1, 0).getDate();
  const yearStart = new Date(monthAnchor.getFullYear(), 0, 1, 12);

  function openDay(index: number) {
    if (index < 0 || !days[index]) return;
    setSelectedDay(Math.min(Math.max(index, 0), Math.max(0, days.length - 1)));
    setSelectedEvent(0);
    setRewindMode("day");
    onToast(`Opened ${days[index]?.title || "Rewind Day"}`);
  }

  return (
    <section aria-label="Map" className={`screen app-context active${expanded ? " map-expanded" : ""}`}>
      <Tabs onValueChange={(value) => setMode(value as MapMode)} value={mode}>
        <header className="context-head">
          <button className="back-card" onClick={onBack} type="button">Back to Card</button>
          <span className="context-title">Map · why it understands you this way</span>
          <TabsList className="segment">
            <TabsTab className={`seg${mode === "nebula" ? " active" : ""}`} value="nebula">Nebula</TabsTab>
            <TabsTab className={`seg${mode === "living" ? " active" : ""}`} value="living">Living Model</TabsTab>
            <TabsTab className={`seg${mode === "rewind" ? " active" : ""}`} value="rewind">Rewind</TabsTab>
          </TabsList>
        </header>

        <TabsPanel className={`map-pane nebula${mode === "nebula" ? " active" : ""}`} value="nebula">
          <Sky className="nebula-sky" colors="38453a,859487,d8d6c5" glow={0.22} glowPosition={[0.55, 0.53]} speed={0.3} />
          <div className="map-copy"><small>MAP · {(snapshot?.personalModel.memoryCount ?? 0).toLocaleString()} MEMORIES</small><h1>Why it understands you this way</h1></div>
          <div className="star-field">
            {ambient.map((star, index) => (
              <i
                className="star ambient"
                key={index}
                style={{
                  left: `${star.left}%`,
                  top: `${star.top}%`,
                  "--s": `${star.size}px`,
                  "--o": star.opacity,
                } as CSSProperties}
              />
            ))}
            {nodes.map((node, index) => {
              const position = nodePositions[index];
              if (!position) return null;
              return (
                <span key={`${node.label}-${index}`}>
                  <button
                    aria-label={node.label}
                    className={`star${index === 0 ? " root" : ""}`}
                    onClick={() => setSelectedNode(index)}
                    style={{
                      left: `${position[0]}%`,
                      top: `${position[1]}%`,
                      "--s": `${position[2]}px`,
                      "--o": Math.max(0.45, node.confidence),
                    } as CSSProperties}
                    type="button"
                  />
                  <span className="star-label" style={{ left: `${position[0]}%`, top: `${position[1]}%` }}>{node.label}</span>
                </span>
              );
            })}
          </div>
          <aside className="node-inspector">
            <span className="node-kind">{activeNode?.kind}</span>
            <h2>{activeNode?.title}</h2>
            <div className="node-meta">{activeNode?.meta}<br />changed with the latest model revision</div>
            <div className="node-actions">
              <button className="dark-btn" onClick={() => onNavigate("home:ask")}>Correct</button>
              <button className="dark-btn" onClick={() => setMode("living")}>History</button>
              <button className="dark-btn" onClick={() => { setMode("rewind"); setRewindMode("day"); }}>Evidence</button>
              <button className="dark-btn" onClick={() => setSheet("share")}>Share</button>
            </div>
            <p className="node-note">Dashed edges are inferred. Correct one and the sky redraws itself.</p>
          </aside>
          <div className="map-legend">● bright = recent &nbsp; ● big = weight &nbsp; pulse = new evidence or your correction</div>
        </TabsPanel>

        <TabsPanel className={`map-pane living${mode === "living" ? " active" : ""}`} value="living">
          <article className="living-page">
            <span className="living-kicker">IDENTITY</span>
            <h1>{snapshot?.model.displayName || "You"}</h1>
            <p className="living-lede">{snapshot?.identity.description || "Your Personal Model is forming on this Mac. It will answer instead of describing."}</p>
            <section className="identity-file">
              <div className="identity-head">
                <div className="avatar"><Sky className="sky-canvas" animate={false} colors="e8e4da,c7c2b6,f4f1ea" /></div>
                <div><strong>{snapshot?.model.displayName || "You"}</strong><span>Your Personal Model is learning · since {snapshot?.model.sinceYear || "now"}</span></div>
                <span className="mcp-live">mcp live</span>
              </div>
              <div className="json">{'{'}<br />&nbsp;&nbsp;<span className="key">"name"</span>: <span className="value">"{snapshot?.model.handle || "@you"}"</span>,<br />&nbsp;&nbsp;<span className="key">"model"</span>: <span className="value">"personal-v1"</span>,<br />&nbsp;&nbsp;<span className="key">"trained_on"</span>: <span className="value">"my life, so far"</span>,<br />&nbsp;&nbsp;<span className="key">"talk_to_me"</span>: <span className="value">"this card · /card"</span><br />{'}'}</div>
            </section>
            <div className="model-lines">
              {(snapshot?.personalModel.faces ?? []).slice(0, 4).map((face, index) => (
                <div className="model-line" key={face.id}><span>{face.text}</span><small>FACE {String(index + 1).padStart(2, "0")} · {Math.round(face.confidence * 100)}%</small></div>
              ))}
              {!snapshot?.personalModel.faces.length && <div className="empty-note">Persome needs more observations before it can name a stable pattern.</div>}
            </div>
            <div className="change-line">CHANGE · LATEST REVISION &nbsp; every correction remains attributable to you</div>
          </article>
        </TabsPanel>

        <TabsPanel className={`map-pane rewind${mode === "rewind" ? " active" : ""}`} value="rewind">
          <section className="rewind-sheet">
            <header className="rewind-top">
              <div><span style={{ color: "#aaa", font: "9px var(--mono)" }}>MAP / </span><span className="rewind-date">{day?.title || "No captured day"}{rewindMode === "day" && <small>TODAY</small>}</span></div>
              <div className="rewind-tools">
                <button className="remind-open" onClick={() => setSheet("remind")}>Worth remembering · {snapshot?.now.items.length ?? 0}</button>
                <div className="time-seg">
                  {(["day", "week", "month", "year"] as RewindMode[]).map((value) => (
                    <button className={`time-tab${rewindMode === value ? " active" : ""}`} key={value} onClick={() => setRewindMode(value)}>{value[0].toUpperCase() + value.slice(1)}</button>
                  ))}
                </div>
                <button aria-pressed={expanded} className="rewind-expand" onClick={() => setExpanded((current) => !current)}>{expanded ? "↙ Restore" : "↗ Expand"}</button>
              </div>
            </header>

            <div className={`rewind-view${rewindMode === "day" ? " active" : ""}`}>
              <div className="tv">
                <div className="tv-screen"><div><small>{event?.app || "PERSOME"}</small><h2>{event?.title || "No captured activity"}</h2><p>Screen Recording is off for this window — showing the real text event instead of a fake frame.</p></div></div>
                <div className="tv-bottom"><span>● PERSOME · REWIND · CH {String(selectedEvent + 1).padStart(2, "0")}</span><div className="tv-controls"><button className="tv-control" onClick={() => setSelectedEvent((value) => Math.max(0, value - 1))}>‹</button><button className="tv-control" onClick={() => setSelectedEvent((value) => Math.min(Math.max(0, (day?.events.length ?? 1) - 1), value + 1))}>›</button></div></div>
              </div>
              <div className="event-line"><h3>{event?.title || "Nothing captured"}</h3><span>{event?.time || "—"}</span></div>
              <input className="timeline" disabled={!day?.events.length} max={Math.max(0, (day?.events.length ?? 1) - 1)} min={0} onChange={(event) => setSelectedEvent(Number(event.target.value))} type="range" value={Math.min(selectedEvent, Math.max(0, (day?.events.length ?? 1) - 1))} />
              <div className="time-labels">{(day?.events ?? []).slice(0, 4).map((item) => <span key={item.id}>{item.time}</span>)}</div>
              <div className="app-pills">{Array.from(new Set((day?.events ?? []).map((item) => item.app).filter(Boolean))).slice(0, 5).map((appName, index) => <span className="app-pill" key={appName}><b>{index === 0 ? appName : null}</b>{index > 0 ? appName : null}</span>)}</div>
              <div className="root-line"><small>ROOT · TODAY'S LINE</small><p>{day?.portrait || snapshot?.identity.dailyLine || "A gap stays a gap."}</p></div>
            </div>

            <div className={`rewind-view${rewindMode === "week" ? " active" : ""}`}>
              <div className="week-grid">
                {weekDays.map((item, index) => (
                  <button
                    className={`week-day${index === 6 ? " today" : ""}`}
                    disabled={item.sourceIndex < 0}
                    key={`${item.label}-${index}`}
                    onClick={() => openDay(item.sourceIndex)}
                    style={{ "--h": `${item.height}%` } as CSSProperties}
                  >
                    <span className="week-hours">{item.hours}</span>
                    <i className="week-block" style={{ "--h": `${item.height}%`, "--o": item.opacity } as CSSProperties} />
                    <span className="week-topic">{item.topic}</span><label>{item.label.slice(0, 3)} <b>{item.date}</b></label>
                  </button>
                ))}
              </div>
              <p className="period-summary"><small>GENERATED · THIS WEEK · {weekDays.reduce((sum, item) => sum + (days[item.sourceIndex]?.events.length ?? 0), 0)} EVIDENCE</small>{snapshot?.identity.weeklyLetter.join(" ") || "This week is still forming."}</p>
            </div>

            <div className={`rewind-view${rewindMode === "month" ? " active" : ""}`}>
              <div className="month-grid">
                {["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"].map((label) => <div className="month-label" key={label}>{label}</div>)}
                {Array.from({ length: monthOffset }, (_, index) => <div className="month-day blank" key={`blank-${index}`} />)}
                {Array.from({ length: monthDayCount }, (_, index) => {
                  const calendarDate = new Date(monthAnchor.getFullYear(), monthAnchor.getMonth(), index + 1, 12);
                  const sourceIndex = dayIndex.get(localDateKey(calendarDate)) ?? -1;
                  const source = sourceIndex >= 0 ? days[sourceIndex] : undefined;
                  const activity = source ? 0.12 + source.events.length / maxEvents * 0.78 : 0;
                  return <button className={`month-day${activity === 0 ? " blank" : ""}`} disabled={!source} key={index} onClick={() => openDay(sourceIndex)} style={{ "--a": activity } as CSSProperties}>{index + 1}</button>;
                })}
              </div>
              <p className="period-summary"><small>GENERATED · THIS MONTH · {days.reduce((sum, item) => sum + item.events.length, 0)} EVIDENCE</small>{snapshot?.identity.dailyLine || "This month is still forming."}</p>
            </div>

            <div className={`rewind-view${rewindMode === "year" ? " active" : ""}`}>
              <div className="year-grid">{Array.from({ length: 365 }, (_, index) => { const calendarDate = new Date(yearStart); calendarDate.setDate(index + 1); const sourceIndex = dayIndex.get(localDateKey(calendarDate)) ?? -1; const source = sourceIndex >= 0 ? days[sourceIndex] : undefined; const activity = source ? 0.1 + source.events.length / maxEvents * 0.7 : 0; return <button aria-label={source ? `Open ${source.title}` : `No captured activity on day ${index + 1}`} className="year-cell" disabled={!source} key={index} onClick={() => openDay(sourceIndex)} style={{ "--a": activity } as CSSProperties} />; })}</div>
              <p className="period-summary"><small>GENERATED · LONG VIEW</small>{snapshot?.personalModel.root || "The long view appears as the model accumulates real history."}</p>
            </div>
          </section>
        </TabsPanel>
      </Tabs>

      <div className={`sheet-backdrop${sheet ? " open" : ""}`} onClick={() => setSheet(null)} />
      <aside className={`sheet remind-sheet${sheet === "remind" ? " open" : ""}`}>
        <div className="sheet-head"><span>WORTH REMEMBERING · TODAY</span><button className="sheet-close" onClick={() => setSheet(null)}>×</button></div>
        {(snapshot?.now.items ?? []).slice(0, 3).map((item) => (
          <div className="remind-row" key={item.id}><small>{item.kind.toUpperCase()}</small><div><p>{item.title}</p><button onClick={() => { setSheet(null); setMode("rewind"); setRewindMode("day"); }}>{item.why || item.when} ↗</button></div></div>
        ))}
        {!snapshot?.now.items.length && <div className="empty-note">Nothing is being promoted without evidence.</div>}
      </aside>
      <aside className={`sheet share-sheet${sheet === "share" ? " open" : ""}`}>
        <div className="sheet-head"><span>WHAT LEAVES PERSOME</span><button className="sheet-close" onClick={() => setSheet(null)}>×</button></div>
        <div className="share-layout"><article className="share-card"><Sky className="sky-canvas" colors="e9dfd2,d9a088,96a8d8" glow={0.2} glowPosition={[0.76, 0.14]} speed={0.32} /><small><span>PERSOME · CURRENT</span><span>AS OF NOW</span></small><div className="share-copy"><h2>{activeNode?.title}</h2></div></article><div className="share-side"><h2>A result, not your whole model.</h2><p>The shared card carries a time range and evidence count. It never sends the complete Personal Model.</p><button className="primary" onClick={() => { void navigator.clipboard.writeText(activeNode?.title || ""); onToast("Caption copied"); }}>Copy caption</button></div></div>
      </aside>
    </section>
  );
}
