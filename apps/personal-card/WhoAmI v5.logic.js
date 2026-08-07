const PX = [1,0,0,1,1, 0,1,1,0,0, 0,1,1,1,0, 1,0,1,0,1, 1,1,0,1,1];
const APP_ICON_ROOT = "/assets/app-icons/";
function appIconUrl(name) {
  const value = String(name || "").toLowerCase();
  if (/claude/.test(value)) return APP_ICON_ROOT + "claude.png";
  if (/chatgpt|codex/.test(value)) return APP_ICON_ROOT + "chatgpt.png";
  if (/chrome|browser/.test(value)) return APP_ICON_ROOT + "chrome.png";
  if (/wechat|微信/.test(value)) return APP_ICON_ROOT + "wechat.png";
  if (/lark|feishu|飞书/.test(value)) return APP_ICON_ROOT + "lark.png";
  if (/coast/.test(value)) return APP_ICON_ROOT + "coast.png";
  if (/notes|备忘录/.test(value)) return APP_ICON_ROOT + "notes.png";
  if (/terminal|开发/.test(value)) return APP_ICON_ROOT + "terminal.png";
  if (/finder/.test(value)) return APP_ICON_ROOT + "finder.png";
  return APP_ICON_ROOT + "generic.svg";
}
function memorySignature(event) {
  const primary = [event && event.title, event && event.detail].filter(Boolean).join(" ");
  return (primary || String((event && event.io) || ""))
    .toLowerCase()
    .replace(/personal card|who am i|persome|实时内容|当前任务|工作流|继续整理|继续处理/gi, "")
    .replace(/[\s·，。！？、:：;；\-—_()[\]（）]+/g, "");
}
const REM = [
  ["连接自己的 Personal Model 后，这里会出现只属于你的提醒。", ""],
  ["想说什么，也可以直接说。", ""],
];
const SHADOW_TITLES = {};
const SHADOW_EVENTS = [];
const YEAR_MONTHS = ["FEB","MAR","APR","MAY","JUN","JUL","AUG"];
const STAR_FACTS = [
  { k: "画像", t: "这条画像仍在形成。", r: "Personal Model · waiting", f: "等待个人证据", day: null },
];

function snapshotToLegacyLive(snapshot) {
  const modelId = snapshot?.model?.id || "";
  const identity = snapshot?.identity || {};
  const days = (snapshot?.time?.days || []).map((day) => {
    const events = (day.events || []).map((event) => ({
      t: event.time,
      title: event.title,
      io: event.detail || "",
      detail: event.detail || "",
      frames: [],
      sourceId: event.evidenceRef || `${modelId}:event:${event.id}`,
      receipt: event.evidenceRef || `${modelId}:event:${event.id}`,
      app: event.app || "Personal Model",
    }));
    const appsByName = {};
    events.forEach((event) => {
      const name = event.app || "Personal Model";
      appsByName[name] = (appsByName[name] || 0) + 1;
    });
    return {
      key: day.id,
      n: Number(String(day.id).slice(-2)),
      title: day.title,
      short: String(day.id).slice(5),
      peek: events[0]?.title || day.portrait,
      portrait: day.portrait,
      taught: identity.dailyLine || day.portrait,
      letter: day.letter || "",
      narr: day.portrait,
      lit: [],
      totalTime: `${events.length} memories`,
      apps: Object.entries(appsByName).map(([name, count], index) => [
        name,
        ["#52545B", "#8D6A5A", "#657F72", "#6C7395"][index % 4],
        `${count} ${count === 1 ? "memory" : "memories"}`,
      ]),
      tl: events.map((event, index) => ({
        w: 1,
        c: ["#52545B", "#8D6A5A", "#657F72", "#6C7395"][index % 4],
        ev: index,
        tip: `${event.t} · ${event.title}`,
      })),
      events,
      source: `Personal Model · ${modelId}`,
      coastFrames: [],
      coastSource: `Personal Model · ${modelId}`,
      selfReading: {
        title: "今天的你",
        statement: identity.dailyLine || day.portrait,
        verified: events.slice(0, 3).map((event) => ({
          text: event.detail || event.title,
          receipt: event.receipt,
        })),
        tension: day.portrait,
        letter: String(day.letter || "").split("\n").filter(Boolean),
      },
    };
  });
  const connectors = (snapshot?.connectors || []).map((connector) => ({
    id: connector.id,
    name: connector.name,
    app: connector.product,
    icon: connector.name?.slice(0, 1) || "＋",
    on: connector.status === "connected",
    status: connector.status,
    sessionId: connector.sessionId || "",
    cites: connector.status === "connected" ? "戴着当前 Personal Card" : "",
    revs: [],
  }));
  const proactive = (snapshot?.now?.items || []).map((item) => ({
    id: item.id,
    kind: item.kind,
    title: item.title,
    why: item.why,
    when: item.when,
    day: item.dayId || null,
  }));
  const futureEvents = (snapshot?.now?.items || [])
    .filter((item) => item.kind === "future")
    .map((item) => ({
      id: item.id,
      day: item.dayId || "",
      time: item.when,
      title: item.title,
      detail: item.why,
      confidence: "也许",
      app: "Personal Model",
    }));
  return {
    generatedAt: snapshot?.personalModel?.updatedAt || new Date().toISOString(),
    clockLabel: "as of now",
    monthLabel: String(snapshot?.card?.monthYear || "AUGUST / 2026").split("/")[0].trim(),
    yearLabel: String(snapshot?.card?.monthYear || "AUGUST / 2026").split("/")[1]?.trim() || "",
    observation: identity.dailyLine || "",
    proactive,
    nowItems: proactive.map((item) => ({
      ...item,
      kind: item.kind === "past" ? "过去" : item.kind === "present" ? "现在" : "未来",
      t: item.when,
      app: "Personal Model",
    })),
    proactiveLabel: `${String(snapshot?.card?.monthYear || "AS OF NOW").replace("/", " ")} · LIVE`,
    futureEvents,
    days,
    connectors,
    themes: (snapshot?.personalModel?.faces || []).map((face, index) => ({
      label: face.text,
      sub: `${face.observations} observations`,
      day: days[0]?.key || null,
      color: ["#6C7395", "#657F72", "#8D6A5A", "#52545B"][index % 4],
      rank: index,
    })),
  };
}

class Component extends DCLogic {
  state = {
    opening: true, openingOpen: false,
    view: "home", visitor: false, flipped: false, skyMode: "constellation", skySel: -1, skyFocus: -1, revStep: 0,
    askOpen: false, dockOpen: false, mcpOpen: false, mcpLoading: false, mcpConnecting: "", mcpSwiping: false, mcpSwipeDone: false, mcpTargets: [], mcpEvents: [], mcpError: "", mcpReportOpen: "", mcpConnectorPicker: false,
    revIdx: -1, starRead: -1, starFixing: false, evidenceFocus: null, shareEvidence: null, factFixes: {}, rw: "cal", shareFact: -1, sfSaved: false, dailyUnderline: "",
    ph: "search your life — 或直接问", ri: 0, ans: null,
    activeModelId: null, ownerModelId: null, modelSnapshot: null, modelRevision: 0, loadingModelId: null, switchError: "", devSwitcher: false, modelOptions: [],
    setupRequired: true, setupLoading: true, setupStatus: null, setupError: "", setupMessage: "",
    persomeLoading: true, persomeConnected: false, persomeCount: null, persomeRoot: "", persomeFaces: [], persomeUpdatedAt: "", persomeError: "", persomeLive: {},
    day: null, shadow: false, expanded: -1, fixing: false, portraits: {}, corrected: {}, lit: false, dayAns: null,
    coastIdx: -1, coastFrameFailed: false,
    flying: false, flyFrom: null, flyTo: null, flyGo: false,
    dock: [
      { name: "Claude Code", icon: "✳", tint: "#F5E4D7", fg: "#C1562B", on: false, cites: "", revs: [] },
      { name: "Codex", icon: "⌗", tint: "#DDF0EA", fg: "#0B8A6B", on: false, cites: "", revs: [] },
      { name: "Cursor", icon: "◤", tint: "#E6E6E9", fg: "#1D1D1F", on: false, cites: "", revs: [] },
      { name: "ChatGPT", icon: "◉", tint: "#DDF0EA", fg: "#0B8A6B", on: false, cites: "", revs: [] },
      { name: "Perplexity", icon: "✦", tint: "#DCECEF", fg: "#137A8C", on: false, cites: "", revs: [] },
      { name: "Manus", icon: "M", tint: "#E8E5DE", fg: "#3B3833", on: false, cites: "", revs: [] },
      { name: "Replit", icon: "◆", tint: "#FBE7D6", fg: "#D2611B", on: false, cites: "", revs: [] },
      { name: "Copilot", icon: "◍", tint: "#E2E7F3", fg: "#3155A8", on: false, cites: "", revs: [] }
    ],
    wall: []
  };

  componentDidMount() {
    let i = 0, phase = 0, buf = "";
    this.phT = setInterval(() => {
      if (this.state.view !== "home" || this.state.visitor) return;
      const liveProactive = (this.state.persomeLive && this.state.persomeLive.proactive) || [];
      const promptPool = liveProactive.length
        ? [...liveProactive.map((item) => item.title), "想说什么，也可以直接说。"]
        : [...REM.map((item) => item[0]), "想说什么，也可以直接说。"];
      const t = promptPool[this.state.ri % promptPool.length];
      if (phase === 0) { buf = t.slice(0, ++i); if (i >= t.length) { phase = 1; i = 0; } }
      else if (phase === 1) { if (++i > 23) phase = 2; }
      else { buf = buf.slice(0, -2); if (!buf.length) { phase = 0; i = 0; this.setState({ ri: (this.state.ri + 1) % promptPool.length }); } }
      this.setState({ ph: buf || "search your life — 或直接问" });
    }, 95);
    this.keyNav = e => {
      const st = this.state;
      if (e.key === "Escape") {
        if (st.mcpOpen) { this.setState({ mcpOpen: false }); return; }
        if (st.shareFact >= 0) { this.setState({ shareFact: -1 }); return; }
        if (st.starRead >= 0) { this.setState({ starRead: -1, skySel: -1, skyFocus: -1 }); return; }
        if (st.view !== "home") { this.setState({ view: "home", day: null, dockOpen: false }); return; }
        if (st.dockOpen) { this.setState({ dockOpen: false }); return; }
        if (st.visitor) this.setState({ visitor: false });
        return;
      }
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        this.setState({ view: "home", dockOpen: false }, () => setTimeout(() => { const el = document.querySelector("input"); if (el) el.focus(); }, 60));
        return;
      }
      if (((!st.flipped || st.view !== "home") && st.view !== "sky") || st.starFixing || st.shareFact >= 0) return;
      if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].indexOf(e.key) < 0) return;
      e.preventDefault();
      if (e.key === "ArrowUp") { this.setState({ starRead: 99, skySel: -2, skyFocus: -1, starFixing: false }); return; }
      if (e.key === "ArrowDown") { this.setState({ starRead: -1, skySel: -1, skyFocus: -1 }); return; }
      if (st.view === "sky") {
        const stars = this.skyData().stars;
        const br = stars.map((x, i) => x.bright ? i : -1).filter(i => i >= 0);
        const pos = br.indexOf(st.skySel);
        const step = e.key === "ArrowRight" ? 1 : -1;
        const nx = br[((pos < 0 ? (step > 0 ? -1 : 1) : pos) + step + br.length) % br.length];
        this.setState({ skySel: nx, starRead: stars[nx].fi, skyFocus: stars[nx].ti, starFixing: false });
        return;
      }
      const n = 6, cur = st.starRead >= 0 && st.starRead < n ? st.starRead : (e.key === "ArrowRight" ? -1 : 1);
      this.setState({ starRead: ((e.key === "ArrowRight" ? cur + 1 : cur - 1) + n) % n, starFixing: false });
    };
    window.addEventListener("keydown", this.keyNav);
    this.modelStore = new ActivePersonalModelStore();
    this.unsubscribeModelStore = this.modelStore.subscribe((storeState, event) => {
      if (event.type === "model-switch-start") {
        this.setState({
          loadingModelId: storeState.loadingModelId,
          switchError: "",
          mcpOpen: false,
          mcpReportOpen: "",
          mcpConnectorPicker: false,
          evidenceFocus: null,
          shareEvidence: null,
          shareFact: -1,
          askOpen: false,
          askDrop: false,
          ans: null,
          dockOpen: false,
          view: "home",
          day: null,
          expanded: -1,
          starRead: -1,
          skySel: -1,
          skyFocus: -1,
        });
        return;
      }
      if (event.type === "model-switch-commit") {
        this.applyModelSnapshot(storeState);
        return;
      }
      if (event.type === "model-switch-error") {
        this.setState({
          loadingModelId: null,
          switchError: storeState.switchError || "Personal Model 切换失败",
          persomeLoading: false,
        });
      }
    });
    window.whoamiSwitchModel = (modelId, options) => this.switchModel(modelId, options);
    const query = new URLSearchParams(window.location.search);
    const requestedModelId = query.get("model");
    const requestedAccess = query.get("access") || (query.get("public") === "1" ? "public" : "");
    const wantsDevelopmentContext = query.get("dev") === "1" || !!requestedModelId;
    const begin = async () => {
      try {
        const setupResponse = await fetch("/api/setup/status", {
          credentials: "same-origin",
          cache: "no-store",
        });
        const setupPayload = await setupResponse.json();
        if (setupResponse.ok) {
          this.setState({
            setupLoading: false,
            setupStatus: setupPayload,
            setupRequired: true,
          });
          if (!setupPayload.ready) return;
        } else {
          this.setState({
            setupLoading: false,
            setupRequired: true,
            setupError: setupPayload?.error || "无法检测这台 Mac 上的 Personal Model",
          });
          return;
        }
      } catch {
        this.setState({
          setupLoading: false,
          setupRequired: true,
          setupError: "无法检测这台 Mac 上的 Personal Model",
        });
        return;
      }
      let developmentAllowed = false;
      if (wantsDevelopmentContext || !this.state.ownerModelId) {
        try {
          const response = await fetch("/api/models", { credentials: "same-origin" });
          const payload = await response.json();
          developmentAllowed = !!payload?.devMode;
          this.setState({ ownerModelId: payload?.ownerModelId || null });
          if (developmentAllowed && query.get("dev") === "1" && Array.isArray(payload.models)) {
            this.setState({ devSwitcher: true, modelOptions: payload.models });
          }
        } catch {}
      }
      const initialModelId = developmentAllowed ? requestedModelId : "";
      const access = requestedAccess;
      this.loadPersome(false, initialModelId, access);
    };
    begin();
    this.persomeT = setInterval(() => this.loadPersome(true), 5 * 60 * 1000);
  }
  componentWillUnmount() {
    clearInterval(this.phT);
    clearInterval(this.revT);
    clearInterval(this.persomeT);
    clearTimeout(this.persomeRetryT);
    clearTimeout(this.flyT);
    clearTimeout(this.toastT);
    if (this.unsubscribeModelStore) this.unsubscribeModelStore();
    if (this.modelStore) this.modelStore.destroy();
    if (window.whoamiSwitchModel) delete window.whoamiSwitchModel;
    window.removeEventListener("keydown", this.keyNav);
  }

  async refreshSetup() {
    if (this.state.setupLoading) return;
    this.setState({ setupLoading: true, setupError: "", setupMessage: "" });
    try {
      const response = await fetch("/api/setup/status", {
        credentials: "same-origin",
        cache: "no-store",
      });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "无法检测 Personal Model");
      this.setState({
        setupLoading: false,
      setupStatus: payload,
      setupRequired: true,
      setupMessage: payload.ready ? "你的 Personal Model 已连接" : "",
      });
      if (payload.ready) {
        const modelsResponse = await fetch("/api/models", { credentials: "same-origin" });
        const modelsPayload = await modelsResponse.json();
        this.setState({ ownerModelId: modelsPayload?.ownerModelId || null });
        await this.loadPersome(false);
      }
    } catch (error) {
      this.setState({
        setupLoading: false,
        setupError: error?.message || "暂时无法检测 Personal Model",
      });
    }
  }

  async saveSetupProfile() {
    if (this.state.setupLoading) return;
    const read = (name) => document.querySelector(`[data-setup-${name}]`)?.value || "";
    this.setState({ setupLoading: true, setupError: "", setupMessage: "" });
    try {
      const response = await fetch("/api/setup/profile", {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          displayName: read("name"),
          handle: read("handle"),
          tagline: read("tagline"),
          description: read("description"),
        }),
      });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "无法创建 Personal Card");
      this.setState({
        setupLoading: false,
      setupStatus: payload,
      setupRequired: true,
        setupMessage: payload.ready
          ? "你的卡已经创建"
          : "卡已创建，下一步连接本机 Personal Model",
      });
      if (payload.ready) await this.refreshSetup();
    } catch (error) {
      this.setState({
        setupLoading: false,
        setupError: error?.message || "无法创建 Personal Card",
      });
    }
  }

  async launchPersonalModelSetup() {
    if (this.state.setupLoading) return;
    this.setState({ setupLoading: true, setupError: "", setupMessage: "" });
    try {
      const response = await fetch("/api/setup/personal-model", {
        method: "POST",
        credentials: "same-origin",
      });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "无法打开安装向导");
      this.setState({
        setupLoading: false,
        setupMessage: "安装与权限向导已在 Terminal 打开；完成后回到这里重新检测。",
      });
    } catch (error) {
      this.setState({
        setupLoading: false,
        setupError: error?.message || "无法打开安装向导",
      });
    }
  }

  async persomeApi(path, options) {
    if (!this.modelStore) throw new Error("Personal Model Store 尚未就绪");
    const route = {
      "/ask": "/api/model/ask",
      "/reflect": "/api/model/ask",
      "/correct": "/api/model/correct",
      "/mcp/status": "/api/model/connectors",
      "/mcp/events": "/api/model/reports",
    }[path] || path;
    return this.modelStore.request(route, options || {});
  }

  applyModelSnapshot(storeState) {
    const snapshot = storeState.snapshot;
    const personalModel = snapshot?.personalModel || {};
    this.persomeRetries = 0;
    this._sky = null;
    this.setState({
      activeModelId: storeState.activeModelId,
      modelSnapshot: snapshot,
      modelRevision: storeState.revision,
      loadingModelId: null,
      switchError: "",
      visitor: snapshot?.authorization?.viewerMode === "public",
      persomeLoading: false,
      persomeConnected: true,
      persomeCount: Number.isFinite(personalModel.memoryCount) ? personalModel.memoryCount : null,
      persomeRoot: personalModel.root || "",
      persomeFaces: Array.isArray(personalModel.faces) ? personalModel.faces : [],
      persomeUpdatedAt: personalModel.updatedAt || "",
      persomeLive: snapshotToLegacyLive(snapshot),
      mcpTargets: [],
      mcpEvents: [],
      mcpReportsData: [],
      mcpSwipeDone: false,
      persomeError: "",
      setupRequired: false,
    });
  }

  async switchModel(modelId, options) {
    if (!this.modelStore) throw new Error("Personal Model Store 尚未就绪");
    return this.modelStore.switchModel(modelId, options || {});
  }

  async loadPersome(silent, modelId, access) {
    if (!silent) this.setState({ persomeLoading: true });
    try {
      await this.modelStore.bootstrap({
        modelId: modelId || undefined,
        access: access || undefined,
      });
    } catch (error) {
      this.setState({
        persomeLoading: false,
        persomeConnected: !!this.state.modelSnapshot,
        persomeError: error && error.message ? error.message : "Persome 暂时不可用",
        setupRequired: !this.state.modelSnapshot,
        setupStatus: !this.state.modelSnapshot
          ? { ...(this.state.setupStatus || {}), state: "runtime_unavailable" }
          : this.state.setupStatus,
      });
      if (!silent && (this.persomeRetries || 0) < 3) {
        this.persomeRetries = (this.persomeRetries || 0) + 1;
        clearTimeout(this.persomeRetryT);
        this.persomeRetryT = setTimeout(() => this.loadPersome(), 1800 * this.persomeRetries);
      }
    }
  }

  async loadMcp(silent) {
    if (!silent) this.setState({ mcpLoading: true, mcpError: "" });
    try {
      const [status, history] = await Promise.all([
        this.persomeApi("/mcp/status"),
        this.persomeApi("/mcp/events")
      ]);
      this._sky = null;
      const rawTargets = Array.isArray(status.connectors) ? status.connectors : Array.isArray(status.targets) ? status.targets : [];
      const targets = rawTargets.map((target) => ({
        ...target,
        observed: target.observed ?? target.status === "connected",
        installed: target.installed ?? target.status !== "missing",
        iconUrl: target.iconUrl || appIconUrl(target.id || target.name),
      }));
      this.setState({
        mcpLoading: false,
        mcpTargets: targets,
        mcpEvents: Array.isArray(history.events) ? history.events : [],
        mcpReportsData: Array.isArray(history.reports) ? history.reports : [],
        mcpSwipeDone: targets.length > 0 && targets.every((target) => target.status === "connected" || target.observed),
        mcpError: ""
      });
    } catch (error) {
      this.setState({
        mcpLoading: false,
        mcpError: error && error.message ? error.message : "暂时无法读取 MCP 状态"
      });
    }
  }

  hasModelScope(scope) {
    return (this.state.modelSnapshot?.authorization?.scopes || []).includes(scope);
  }

  openMcp() {
    if (!this.hasModelScope("connectors:read")) return;
    this.setState({ mcpOpen: true, dockOpen: false, askDrop: false, mcpError: "" }, () => this.loadMcp());
  }

  async connectMcp(agent) {
    if (!this.hasModelScope("connectors:connect") || !agent || this.state.mcpConnecting) return;
    this.setState({ mcpConnecting: agent, mcpError: "" });
    try {
      await this.modelStore.request(`/api/model/connectors/${encodeURIComponent(agent)}/connect`, {
        method: "POST",
        body: {}
      });
      await this.loadMcp(true);
    } catch (error) {
      this.setState({ mcpError: error && error.message ? error.message : "MCP 接入失败" });
    } finally {
      this.setState({ mcpConnecting: "" });
    }
  }

  async swipeMcpCard() {
    if (!this.hasModelScope("connectors:connect") || this.state.mcpSwiping || this.state.mcpConnecting || this.state.mcpLoading) return;
    const targets = Array.isArray(this.state.mcpTargets) ? this.state.mcpTargets : [];
    if (!targets.length) {
      this.loadMcp();
      return;
    }
    const pending = targets.filter((target) => !target.observed);
    this.setState({ mcpSwiping: true, mcpSwipeDone: false, mcpError: "" });
    await new Promise((resolveSwipe) => setTimeout(resolveSwipe, 900));
    const failures = [];
    for (const target of pending) {
      this.setState({ mcpConnecting: target.id });
      try {
        await this.modelStore.request(`/api/model/connectors/${encodeURIComponent(target.id)}/connect`, {
          method: "POST",
          body: {}
        });
      } catch (error) {
        failures.push(`${target.id === "codex" ? "GPT" : "Claude"} 暂时没有连接成功，请确认应用已经安装。`);
      }
    }
    await this.loadMcp(true);
    this.setState({
      mcpConnecting: "",
      mcpSwiping: false,
      mcpSwipeDone: failures.length === 0,
      mcpError: failures.join(" ")
    });
  }

  evidencePool() {
    const live = this.state.persomeLive || {};
    const fromDays = (Array.isArray(live.days) ? live.days : []).flatMap((day) =>
      (Array.isArray(day.events) ? day.events : []).map((event, eventIndex) => ({
        id: event.sourceId || event.receipt || `rewind_${day.key}_${eventIndex}`,
        kind: "REWIND · EVIDENCE",
        title: event.title || "一个真实事件",
        detail: event.detail || event.io || "",
        day: day.key,
        eventIndex,
        receipt: event.sourceId || event.receipt || `event_${eventIndex + 1}`,
      }))
    );
    const fromMcp = (this.state.mcpEvents || []).map((event) => ({
      id: event.evidenceId || event.id,
      kind: `${event.agent === "codex" ? "GPT" : "CLAUDE"} · PERSONAL MODEL`,
      title: event.summary || `调用 ${event.tool || "Persome"}`,
      detail: `${event.tool || "Persome"} · ${event.durationMs || 0}ms · ${event.status === "error" ? "调用失败" : "已留下真实调用记录"}`,
      day: event.day,
      receipt: event.receipt || event.evidenceId || event.id,
      agent: event.agent,
      tool: event.tool,
    }));
    return [...fromMcp, ...fromDays].filter((item) => item.id);
  }

  openEvidenceSky(evidence) {
    if (!this.hasModelScope("evidence:read")) return;
    const target = typeof evidence === "string"
      ? this.evidencePool().find((item) => item.id === evidence)
      : evidence;
    const data = this.skyData();
    const matching = data.stars.findIndex((star) => star.bright && target && star.evidence && star.evidence.id === target.id);
    const bright = data.stars.map((star, index) => star.bright ? index : -1).filter((index) => index >= 0);
    const seed = String(target?.id || "evidence").split("").reduce((sum, char) => (sum * 31 + char.charCodeAt(0)) >>> 0, 0);
    const index = matching >= 0 ? matching : bright[seed % Math.max(1, bright.length)];
    const star = data.stars[index] || {};
    this.setState({
      view: "sky",
      mcpOpen: false,
      dockOpen: false,
      skyMode: "constellation",
      skySel: index,
      skyFocus: star.ti == null ? -1 : star.ti,
      starRead: star.fi >= 0 ? star.fi : 0,
      starFixing: false,
      evidenceFocus: target || star.evidence || null,
    });
  }

  async askPersome(question, visitor) {
    if (!this.hasModelScope("model:ask")) return;
    this.setState({ askDrop: false, ans: ["正在从你的 Personal Model 里找答案…", "Persome · 本机查询中", null] });
    try {
      const data = await this.persomeApi("/ask", {
        method: "POST",
        body: JSON.stringify({ question })
      });
      const meta = "Persome · " + (data.tools || ["behavior_patterns", "search"]).join(" + ") + " · " + (data.latencyMs || 0) + "ms";
      this.setState({ ans: [data.answer || "这次没有找到足够清晰的依据。", visitor ? "— shared model · " + meta : meta, null] });
    } catch (error) {
      this.setState({
        persomeError: error && error.message ? error.message : "Persome 暂时不可用",
        ans: ["本机 Personal Model 暂时无法回答。恢复连接后再试一次。", "Persome · 未返回个人依据", null]
      });
    }
  }

  async reflectPersome(text) {
    if (!this.hasModelScope("model:ask")) return;
    this.setState({
      askOpen: true,
      askDrop: false,
      ans: ["我先听你说完，再把相关的你还给你…", "Personal Model · 正在回看", null]
    });
    try {
      const data = await this.persomeApi("/reflect", {
        method: "POST",
        body: JSON.stringify({ text })
      });
      this.setState({
        ans: [data.answer || "我记下了这一刻。现在还没有足够的过去来照见它。", "倾诉 · 只返回观察，不替你做决定", data.day || null]
      });
    } catch (error) {
      this.setState({
        ans: ["我听见了。现在先不解释，也不把它变成待办；这句话会留在这里，等更多的你慢慢靠近。", "Personal Model · 暂时没有找到相关证据", null]
      });
    }
  }

  async correctPersome(correction) {
    if (!this.hasModelScope("model:correct") || !this.state.persomeConnected || !correction) return;
    try {
      await this.persomeApi("/correct", {
        method: "POST",
        body: JSON.stringify({ correction })
      });
    } catch (error) {
      this.setState({
        persomeError: error && error.message ? error.message : "更正尚未写入 Persome"
      });
    }
  }

  openDay(n, shadow) {
    if (!this.hasModelScope("rewind:read")) return;
    this.setState({ view: "day", day: n, shadow, expanded: -1, fixing: false, lit: false, dayAns: null, coastIdx: -1, coastFrameFailed: false, dailyUnderline: "" }, () => {
      if (!shadow) setTimeout(() => this.setState({ lit: true }), 320);
    });
  }

  saveShareImage(kind, value, meta, byline) {
    try {
      const canvas = document.createElement("canvas");
      canvas.width = 960;
      canvas.height = 1200;
      const ctx = canvas.getContext("2d");
      ctx.fillStyle = "#F8F4EB";
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.strokeStyle = "#E4DED2";
      ctx.lineWidth = 2;
      ctx.strokeRect(28, 28, 904, 1144);
      const wrap = (text, maxWidth, font, maxLines = 10) => {
        ctx.font = font;
        const lines = [];
        let line = "";
        for (const char of String(text || "")) {
          if (char === "\n") {
            if (line) lines.push(line);
            line = "";
            if (lines.length >= maxLines) break;
            continue;
          }
          const next = line + char;
          if (line && ctx.measureText(next).width > maxWidth) {
            lines.push(line);
            line = char;
            if (lines.length >= maxLines) break;
          } else {
            line = next;
          }
        }
        if (line && lines.length < maxLines) lines.push(line);
        if (lines.length === maxLines && String(text || "").length > lines.join("").length) {
          lines[maxLines - 1] = lines[maxLines - 1].replace(/[，。；、\s]+$/, "") + "…";
        }
        return lines;
      };
      ctx.fillStyle = "#9A968F";
      ctx.font = "22px ui-monospace, Menlo, monospace";
      ctx.fillText(String(kind || "TODAY").toUpperCase(), 86, 105);
      const lines = wrap(value, 788, "52px 'Songti SC', 'Times New Roman', serif", 9);
      ctx.fillStyle = "#2E2B26";
      ctx.font = "52px 'Songti SC', 'Times New Roman', serif";
      let y = 210;
      for (const line of lines) {
        ctx.fillText(line, 86, y);
        y += 88;
      }
      ctx.strokeStyle = "#2E2B26";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(86, Math.min(y + 12, 910));
      ctx.lineTo(250, Math.min(y + 12, 910));
      ctx.stroke();
      ctx.fillStyle = "#9A968F";
      ctx.font = "22px ui-monospace, Menlo, monospace";
      const metaLines = wrap(meta, 788, "22px ui-monospace, Menlo, monospace", 2);
      let metaY = Math.min(y + 80, 980);
      for (const line of metaLines) {
        ctx.fillText(line, 86, metaY);
        metaY += 34;
      }
      ctx.strokeStyle = "#DED8CD";
      ctx.beginPath();
      ctx.moveTo(86, 1040);
      ctx.lineTo(874, 1040);
      ctx.stroke();
      ctx.fillStyle = "#2E2B26";
      ctx.font = "600 26px -apple-system, BlinkMacSystemFont, sans-serif";
      const activeModel = this.state.modelSnapshot?.model || {};
      ctx.fillText(`${activeModel.handle || "@personal-model"} · № ${activeModel.memberNumber || "001"}`, 86, 1096);
      ctx.fillStyle = "#9A968F";
      ctx.font = "20px ui-monospace, Menlo, monospace";
      ctx.fillText(byline || "personal model said this", 86, 1132);
      const link = document.createElement("a");
      link.download = `WhoAmI-${new Date().toISOString().slice(0, 10)}.png`;
      link.href = canvas.toDataURL("image/png");
      document.body.appendChild(link);
      link.click();
      link.remove();
      this.setState({ sfSaved: true });
    } catch {
      this.setState({ sfSaved: true });
    }
  }

  startRev(i) {
    clearInterval(this.revT);
    if (i < 0) { this.setState({ revIdx: -1 }); return; }
    this.setState({ revIdx: i, revStep: 0 });
    this.revT = setInterval(() => {
      const connected = (this.state.persomeLive && this.state.persomeLive.connectors) || [];
      const source = this.state.modelSnapshot && connected.length ? connected : this.state.dock;
      const max = ((source[i] && source[i].revs) || []).length + 1;
      const n = (this.state.revStep || 0) + 1;
      this.setState({ revStep: n });
      if (n >= max) clearInterval(this.revT);
    }, 620);
  }

  skyData() {
    if (this._sky) return this._sky;
    const liveThemes = ((this.state.persomeLive || {}).themes || []).slice(0, 6);
    const evidencePool = this.evidencePool();
    const POS = [[38,42],[68,24],[67,66],[22,24],[18,64],[85,46]];
    const hexRgb = hex => {
      const raw = String(hex || "#8FA6FF").replace("#", "");
      const value = raw.length === 3 ? raw.split("").map(x => x + x).join("") : raw;
      return [0, 2, 4].map(i => parseInt(value.slice(i, i + 2), 16) || 143).join(",");
    };
    const THEMES = liveThemes.map((theme, i) => ({
      n: theme.label,
      x: POS[i][0],
      y: POS[i][1],
      s: Math.max(4, 16 - i * 2),
      day: theme.day,
      sub: theme.sub,
      cc: hexRgb(theme.color)
    }));
    const stars = [], edges = [], labels = [];
    THEMES.forEach((t, ti) => {
      const hubs = [];
      for (let i = 0; i < t.s; i++) {
        const a = (i * 137.5 + ti * 61) * Math.PI / 180;
        const rr = (ti === 0 ? 13 : 9) * Math.sqrt(((i * 2654435761) % 97) / 97);
        const x = t.x + Math.cos(a) * rr, y = t.y + Math.sin(a) * rr * .85;
        const bright = i === 0 || i % 4 === 1;
        const age = (i * 5 + ti * 3) % 28;
        const ta = ((i * 89 + ti * 137) % 360) * Math.PI / 180;
        const tr = 7 + age / 28 * 34;
        const evidence = bright && evidencePool.length
          ? evidencePool[(ti * 7 + i) % evidencePool.length]
          : null;
        stars.push({ x, y, tx: 50 + Math.cos(ta) * tr, ty: 46 + Math.sin(ta) * tr * .8, bright, big: i === 0, age, ti, fi: bright ? (ti * 3 + i) % STAR_FACTS.length : -1, evidence });
        if (bright && hubs.length < 5) hubs.push(stars.length - 1);
      }
      for (let hh = 1; hh < hubs.length; hh++) edges.push({ a: hubs[hh - 1], b: hubs[hh], ti });
      if (hubs.length) edges.push({ a: -1, b: hubs[0], ti });
      labels.push({ n: t.n, x: t.x, y: t.y - (ti === 0 ? 17 : 12), sub: t.sub, day: t.day });
    });
    for (let i = 0; i < 18; i++) stars.push({ x: (i * 137) % 99 + .5, y: (i * 71) % 92 + 4, tx: (i * 137) % 99 + .5, ty: (i * 71) % 92 + 4, bright: false, dim: true, age: 20, ti: -1, fi: -1 });
    this._sky = { stars, edges, labels, themes: THEMES };
    return this._sky;
  }

  swipe(i, e) {
    if (this.state.flying) return;
    const tile = e.currentTarget.getBoundingClientRect();
    const card = document.querySelector("[data-hero-card]");
    const cr = card ? card.getBoundingClientRect() : null;
    this.setState({
      flying: true, flyGo: false,
      flyFrom: cr ? { x: cr.left + cr.width / 2, y: cr.top + cr.height / 2 } : { x: window.innerWidth / 2, y: window.innerHeight * 0.33 },
      flyTo: { x: tile.left + tile.width / 2, y: tile.top + tile.height / 2 }
    }, () => {
      requestAnimationFrame(() => requestAnimationFrame(() => this.setState({ flyGo: true })));
      this.flyT = setTimeout(() => {
        const dock = this.state.dock.slice();
        dock[i] = Object.assign({}, dock[i], { on: true, cites: "刚刚接入 · 0 次引用", snap: Date.now() });
        this.setState({ flying: false, dock, revIdx: i, revStep: 99 });
      }, 640);
    });
  }

  yearCells() {
    const out = [], total = 28 * 7; // 28 周 ≈ 191 天
    for (let i = 0; i < total; i++) {
      const wk = Math.floor(i / 7), r = (i * 2654435761) % 97;
      let lv = 0;
      const prog = wk / 27;
      if (wk >= 27) { // 未来影子
        out.push({ bg: "transparent", border: "1px dashed #D8D5CE", cur: "pointer", title: "shadow · 还没发生", tap: () => this.openDay(6, true) });
        continue;
      }
      if (prog > 0.9 && r % 3 !== 0) lv = r % 5 === 0 ? 3 : 2;
      else if (prog > 0.72 && r % 4 === 0) lv = r % 5 === 0 ? 2 : 1;
      else if (prog > 0.4 && r % 11 === 0) lv = 1;
      else if (r % 31 === 0) lv = 1;
      const cites = lv === 3 ? 30 + r % 40 : lv === 2 ? 10 + r % 15 : lv === 1 ? 1 + r % 8 : 0;
      out.push({
        bg: lv === 3 ? "#2B47E0" : lv === 2 ? "rgba(43,71,224,.45)" : lv === 1 ? "rgba(43,71,224,.16)" : "#F4F3F0",
        border: "none", cur: lv ? "pointer" : "default",
        title: cites ? cites + " citations · ≈ 人类 " + (cites * 0.11).toFixed(1) + " 天" : "",
        tap: lv ? () => this.setState({ view: "month" }) : null
      });
    }
    return out;
  }

  stars() {
    if (this._stars) return this._stars;
    const out = [];
    // 三团星云：绿=points，橙=lines 区，外散
    const clusters = [[28, 40, 16, 34], [66, 56, 14, 26], [46, 72, 11, 18], [76, 26, 9, 12]];
    clusters.forEach(([cx, cy, rad, n], ci) => {
      for (let i = 0; i < n; i++) {
        const a = (i * 137.5 + ci * 40) * Math.PI / 180, rr = rad * Math.sqrt(((i * 2654435761) % 97) / 97);
        const x = cx + Math.cos(a) * rr, y = cy + Math.sin(a) * rr * .8;
        const r = (i * 7 + ci * 13) % 11;
        const blue = r === 0 && i % 3 === 0, dim = r === 1 || r === 2;
        const sz = blue ? 3 : !dim && i % 5 === 0 ? 2.5 : 1.6;
        out.push({ style: {
          position: "absolute", left: x + "%", top: y + "%",
          width: sz + "px", height: sz + "px", borderRadius: "50%",
          background: blue ? "#8FA6FF" : "rgba(245,245,244," + (dim ? .3 : .75) + ")",
          boxShadow: sz > 2 ? "0 0 5px " + (blue ? "rgba(143,166,255,.7)" : "rgba(245,245,244,.55)") : "none",
          animation: i % 4 === 0 ? "wPulse " + (3 + i % 5) + "s ease-in-out " + (i % 7) / 3 + "s infinite" : "none"
        } });
      }
    });
    this._stars = out;
    return out;
  }

  gNodes() {
    const liveThemes = ((this.state.persomeLive || {}).themes || []).slice(0, 6);
    const POS = [[42,44],[68,26],[66,66],[22,26],[18,62],[86,48]];
    if (liveThemes.length) return liveThemes.map((theme, i) => ({
      label: theme.label,
      sub: theme.sub,
      x: POS[i][0],
      y: POS[i][1],
      r: Math.max(22, 58 - i * 7),
      hot: i === 0,
      day: theme.day
    }));
    return [];
  }

  legacyCalendar() {
    const out = [];
    const base = { position: "relative", height: "52px", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", fontSize: "13px", borderRadius: "9px" };
    const dot = { display: "block", width: "3px", height: "3px", borderRadius: "50%", background: "transparent", marginTop: "3px" };
    const now = new Date();
    const leading = (new Date(now.getFullYear(), now.getMonth(), 1).getDay() + 6) % 7;
    const count = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    for (let i = 0; i < leading; i++) out.push({ n: "", style: base, emStyle: {}, dotStyle: dot, hover: "", peek: false });
    for (let n = 1; n <= count; n++) {
      const today = n === now.getDate();
      out.push({
        n: String(n),
        style: Object.assign({}, base, { color: today ? "#1D1D1F" : "#B8B5AE", cursor: "default", fontWeight: today ? 600 : 400 }),
        emStyle: today
          ? { fontStyle: "normal", display: "inline-grid", placeItems: "center", width: "26px", height: "26px", borderRadius: "8px", boxShadow: "inset 0 0 0 1.5px #1D1D1F", fontSize: "12px" }
          : { fontStyle: "normal" },
        dotStyle: today ? { ...dot, background: "#1D1D1F" } : dot,
        hover: "",
        peek: false,
        tap: null,
      });
    }
    while (out.length % 7) out.push({ n: "", style: base, emStyle: {}, dotStyle: dot, hover: "", peek: false });
    return out;
  }

  calendar() {
    const live = this.state.persomeLive || {};
    const liveDays = (live.days || []);
    const futureEvents = Array.isArray(live.futureEvents) ? live.futureEvents : [];
    if (!this.state.modelSnapshot || !liveDays.length) return this.legacyCalendar();
    const now = new Date();
    const year = now.getFullYear(), month = now.getMonth();
    const first = new Date(year, month, 1);
    const leading = (first.getDay() + 6) % 7;
    const count = new Date(year, month + 1, 0).getDate();
    const byKey = {};
    liveDays.forEach(day => { byKey[day.key] = day; });
    const futureByKey = {};
    futureEvents.forEach((event) => {
      if (!futureByKey[event.day]) futureByKey[event.day] = [];
      futureByKey[event.day].push(event);
    });
    const out = [];
    const base = { position: "relative", height: "52px", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", fontSize: "13px", borderRadius: "9px" };
    const dot = { display: "block", width: "3px", height: "3px", borderRadius: "50%", background: "transparent", marginTop: "3px" };
    for (let i = 0; i < leading; i++) out.push({ n: "", style: base, emStyle: {}, dotStyle: dot, hover: "", peek: false });
    for (let n = 1; n <= count; n++) {
      const key = year + "-" + String(month + 1).padStart(2, "0") + "-" + String(n).padStart(2, "0");
      const day = byKey[key], future = futureByKey[key] || [], today = n === now.getDate();
      const canOpen = !!day || future.length > 0;
      out.push({
        n: String(n),
        style: Object.assign({}, base, { color: day ? "#FFFFFF" : future.length ? "#5F5E59" : today ? "#1D1D1F" : "#B8B5AE", cursor: canOpen ? "pointer" : "default", fontWeight: day || future.length || today ? 600 : 400 }),
        emStyle: day ? { fontStyle: "normal", display: "inline-grid", placeItems: "center", width: "26px", height: "26px", borderRadius: "8px", background: "#2C2C2E", boxShadow: "0 5px 14px -6px rgba(0,0,0,.48)", fontSize: "12px" }
          : future.length ? { fontStyle: "normal", display: "inline-grid", placeItems: "center", width: "26px", height: "26px", borderRadius: "8px", boxShadow: "inset 0 0 0 1px #C7C4BD", fontSize: "12px", color: "#5F5E59", background: "rgba(255,255,255,.34)" }
          : today ? { fontStyle: "normal", display: "inline-grid", placeItems: "center", width: "26px", height: "26px", borderRadius: "8px", boxShadow: "inset 0 0 0 1.5px #1D1D1F", fontSize: "12px", color: "#1D1D1F" }
          : { fontStyle: "normal" },
        dotStyle: today ? { display: "block", width: "3px", height: "3px", borderRadius: "50%", background: "#1D1D1F", marginTop: "3px", animation: "wPulse 1.6s infinite" } : dot,
        predictionOn: future.length > 0,
        predictionMarks: future.slice(0, 3).map(() => ({ style: { display: "block", width: "7px", height: "1px", borderRadius: "1px", background: "#8E8D88" } })),
        hover: canOpen ? "background:#EEECE7" : "",
        peek: canOpen,
        peekT: future.length ? `明天的影子 · ${future.length} 个片段` : day ? day.peek : "",
        tap: canOpen ? () => this.openDay(key, false) : null
      });
    }
    while (out.length % 7) out.push({ n: "", style: base, emStyle: {}, dotStyle: dot, hover: "", peek: false });
    return out;
  }

  renderVals() {
    const s = this.state;
    const hasSnapshot = !!s.modelSnapshot;
    const snapshot = s.modelSnapshot || {};
    const activeModel = snapshot.model || {
      id: "personal-model",
      displayName: "Personal Model",
      handle: "@personal-model",
      memberNumber: "001",
      sinceYear: 2026,
      status: "snapshot",
    };
    const modelCard = snapshot.card || {
      monthYear: "AUGUST / 2026",
      tagline: "Building a model of myself",
      publicUrl: "pm.app/model",
      material: this.props.cardFace ?? "titanium",
      glyph: PX.map(Boolean),
    };
    const modelIdentity = snapshot.identity || {
      description: "Building a model of myself",
      dailyLine: "",
      weeklyLetter: [],
    };
    const activeGlyph = Array.isArray(modelCard.glyph) && modelCard.glyph.length === 25
      ? modelCard.glyph
      : PX.map(Boolean);
    const modelAuthorization = snapshot.authorization || { viewerMode: "owner", scopes: [] };
    const modelScopes = new Set(modelAuthorization.scopes || []);
    const live = s.persomeLive || {};
    const liveDays = Array.isArray(live.days) ? live.days : [];
    const futureEvents = Array.isArray(live.futureEvents) ? live.futureEvents : [];
    const liveDayMap = {};
    liveDays.forEach(item => { liveDayMap[item.key] = item; });
    const futureByDay = {};
    futureEvents.forEach((event) => {
      if (!futureByDay[event.day]) futureByDay[event.day] = [];
      futureByDay[event.day].push(event);
    });
    Object.entries(futureByDay).forEach(([key, events]) => {
      if (liveDayMap[key]) return;
      liveDayMap[key] = {
        key,
        n: Number(String(key).slice(-2)),
        title: events[0].dateTitle || key,
        short: events[0].when || key,
        peek: `明天的影子 · ${events.length} 个片段`,
        portrait: "这不是计划，只是最近的节奏在明天投下的影子。",
        taught: `明天的影子 · ${events.length} 个片段`,
        letter: "",
        narr: "明天还没有发生。这里只留下几种可能，等现实来改写。",
        lit: [],
        totalTime: `${events.length} possibilities`,
        apps: [],
        tl: events.map((event, index) => ({ w: 1, c: ["#B8B5AE", "#D0CDC6", "#9F9C95"][index % 3], ev: index, tip: event.time + " · " + event.title })),
        events: events.map((event) => ({ t: event.time, title: event.title, io: event.confidence || "也许", detail: event.detail, frames: [], sourceId: event.id, app: event.app })),
        source: "Persome · 明天的影子",
        coastFrames: [],
        coastSource: "明天还没有发生",
        futureDay: true,
      };
    });
    const latestDayKey = liveDays.length ? liveDays[0].key : null;
    const modelFaces = (s.persomeFaces || []).length
      ? s.persomeFaces
      : [{ text: "这条画像仍在形成。", observations: 0, confidence: 0 }];
    const liveFacts = modelFaces.map((face, i) => {
      return {
        k: "画像",
        t: face.text || "这条画像仍在形成。",
        r: "face_live_" + String(i + 1).padStart(2, "0") + " · evidence " + (face.observations || "?") + " · confidence " + (face.confidence || "?"),
        f: "Persome · 实时读取",
        day: latestDayKey
      };
    });
    const countValue = Number.isFinite(s.persomeCount) ? s.persomeCount : 0;
    const countText = countValue.toLocaleString("en-US");
    const rootText = s.persomeRoot || "你的 Personal Model 正在形成。";
    const MATS = {
      titanium: {
        face: { color: "#E8E8EA", background: "repeating-linear-gradient(90deg, rgba(255,255,255,.016) 0 1px, transparent 1px 4px), radial-gradient(120% 160% at 22% -24%, rgba(255,255,255,.12), transparent 50%), radial-gradient(90% 120% at 82% 118%, rgba(120,130,160,.1), transparent 55%), linear-gradient(112deg, transparent 33%, rgba(255,255,255,.05) 44%, transparent 55%), linear-gradient(160deg,#48484E,#2E2E33 52%,#232327)", boxShadow: "0 50px 100px -28px rgba(0,0,0,.6), 0 12px 30px -14px rgba(0,0,0,.4), inset 0 0 0 1px rgba(255,255,255,.1), inset 0 1px 0 rgba(255,255,255,.22), inset 0 -1px 0 rgba(0,0,0,.35)" },
        corner: "rgba(232,232,236,.42)", detail: "rgba(242,242,246,.8)",
        name: { color: "#26262B", textShadow: "0 1px 0 rgba(255,255,255,.22), 0 -1px 1px rgba(0,0,0,.55)" },
        pxOn: "rgba(16,16,20,.68)", pxOff: "rgba(255,255,255,.07)"
      },
      ceramic: {
        face: { color: "#4A4741", background: "radial-gradient(120% 160% at 22% -22%, #FFFFFF, transparent 58%), linear-gradient(115deg, transparent 32%, rgba(255,255,255,.85) 42%, transparent 54%), linear-gradient(155deg,#F7F6F2,#E9E7E1)", boxShadow: "0 44px 90px -24px rgba(0,0,0,.28), inset 0 0 0 1px rgba(0,0,0,.05), inset 0 1.5px 0 rgba(255,255,255,.9)" },
        corner: "rgba(110,107,100,.6)", detail: "#57544E",
        name: { color: "#CBC8C0", textShadow: "0 1px 1px rgba(255,255,255,.95), 0 -1px 1px rgba(0,0,0,.22)" },
        pxOn: "#8A8780", pxOff: "rgba(0,0,0,.05)", ink: true
      },
      klein: {
        face: { color: "#EEF1FF", background: "radial-gradient(100% 150% at 20% -20%, rgba(255,255,255,.2), transparent 55%), linear-gradient(115deg, transparent 30%, rgba(255,255,255,.1) 40%, transparent 52%), linear-gradient(155deg,#3350F0,#2338C8 55%,#1B2CA8)", boxShadow: "0 44px 90px -24px rgba(30,51,184,.55), inset 0 0 0 1px rgba(255,255,255,.16), inset 0 1.5px 0 rgba(255,255,255,.3)" },
        corner: "rgba(230,236,255,.55)", detail: "rgba(240,244,255,.9)",
        name: { color: "#16249A", textShadow: "0 1px 1px rgba(255,255,255,.35), 0 -1px 1px rgba(0,0,10,.45)" },
        pxOn: "rgba(240,244,255,.95)", pxOff: "rgba(255,255,255,.14)"
      },
      graphite: {
        face: { color: "#F5F5F4", background: "radial-gradient(90% 140% at 18% -10%, rgba(91,121,255,.14), transparent 52%), linear-gradient(115deg, transparent 34%, rgba(255,255,255,.045) 42%, transparent 50%), linear-gradient(155deg,#1E1E22,#111113)", boxShadow: "0 44px 90px -24px rgba(0,0,0,.55), inset 0 0 0 1px rgba(255,255,255,.07), inset 0 1.5px 0 rgba(255,255,255,.12)" },
        corner: "#6E6E73", detail: "#C8C8CC",
        name: { color: "#0C0C0E", textShadow: "0 1px 1px rgba(255,255,255,.22), 0 -1px 1px rgba(0,0,0,.85)" },
        pxOn: "#F5F5F4", pxOff: "#26262A"
      }
    };
    const mat = MATS[modelCard.material || (this.props.cardFace ?? "titanium")] || MATS.titanium;
    const day = s.day != null && !s.shadow && hasSnapshot ? liveDayMap[s.day] : null;
    const dayFutureEvents = s.day != null ? futureEvents.filter((event) => event.day === String(s.day)) : [];
    const coastFrames = day && Array.isArray(day.coastFrames) ? day.coastFrames : [];
    const coastIdx = coastFrames.length
      ? Math.max(0, Math.min(coastFrames.length - 1, s.coastIdx >= 0 ? s.coastIdx : coastFrames.length - 1))
      : -1;
    const coastFrame = coastIdx >= 0 ? coastFrames[coastIdx] : null;
    const coastTotal = coastFrames.reduce((sum, frame) => sum + Math.max(2, Number(frame.duration) || 2), 0);
    const coastBefore = coastFrames.slice(0, Math.max(0, coastIdx)).reduce((sum, frame) => sum + Math.max(2, Number(frame.duration) || 2), 0);
    const coastCurrentDuration = coastFrame ? Math.max(2, Number(coastFrame.duration) || 2) : 0;
    const coastPlayhead = coastTotal
      ? Math.max(0, Math.min(100, ((coastBefore + coastCurrentDuration / 2) / coastTotal) * 100)).toFixed(2) + "%"
      : "0%";
    const coastAppTotals = {};
    coastFrames.forEach((frame) => {
      const name = frame.app || "Unknown";
      if (!coastAppTotals[name]) coastAppTotals[name] = { name, color: frame.color || "#6E6E73", seconds: 0, frames: 0 };
      coastAppTotals[name].seconds += Math.max(2, Number(frame.duration) || 2);
      coastAppTotals[name].frames += 1;
    });
    const coastMinute = coastFrame && /^\d{2}:\d{2}$/.test(coastFrame.time || "")
      ? Number(coastFrame.time.slice(0, 2)) * 60 + Number(coastFrame.time.slice(3, 5))
      : 0;
    const nearestEventMatch = day && Array.isArray(day.events) && day.events.length
      ? day.events.reduce((best, event) => {
          const minute = /^\d{2}:\d{2}$/.test(event.t || "") ? Number(event.t.slice(0, 2)) * 60 + Number(event.t.slice(3, 5)) : 0;
          return !best || Math.abs(minute - coastMinute) < best.diff ? { event, diff: Math.abs(minute - coastMinute) } : best;
        }, null)
      : null;
    const nearestEvent = nearestEventMatch && nearestEventMatch.diff <= 30 ? nearestEventMatch.event : null;
    const distinctEventIndices = [];
    const distinctEventSignatures = new Set();
    if (day && !day.futureDay && Array.isArray(day.events)) {
      day.events.forEach((event, index) => {
        const signature = memorySignature(event);
        if (!signature || distinctEventSignatures.has(signature)) return;
        distinctEventSignatures.add(signature);
        distinctEventIndices.push(index);
      });
    }
    const highlightCandidates = day && !day.futureDay && Array.isArray(day.events)
      ? distinctEventIndices.slice(-3)
      : [];
    const rewindHighlights = [...new Set(highlightCandidates)]
      .filter((index) => index >= 0 && day?.events?.[index])
      .map((eventIndex) => {
        const event = day.events[eventIndex];
        const eventMinute = /^\d{2}:\d{2}$/.test(event.t || "") ? Number(event.t.slice(0, 2)) * 60 + Number(event.t.slice(3, 5)) : 0;
        const eventText = `${event.title || ""} ${event.io || ""}`;
        const subjectPatterns = [
          /微信|wechat/i,
          /chatgpt|codex/i,
          /chrome|浏览器/i,
          /feishu|飞书/i,
          /claude/i,
          /figma/i,
          /notion/i,
          /notes|备忘录/i,
          /terminal|开发/i,
        ];
        const subject = subjectPatterns.find((pattern) => pattern.test(eventText));
        const matchingFrames = subject
          ? coastFrames.map((frame, index) => ({ frame, index })).filter(({ frame }) => subject.test(`${frame.app || ""} ${frame.title || ""}`))
          : [];
        const framePool = matchingFrames.length
          ? matchingFrames
          : coastFrames.map((frame, index) => ({ frame, index }));
        const frameIndex = coastFrames.length
          ? framePool.reduce((best, { frame, index }) => {
              const frameMinute = /^\d{2}:\d{2}$/.test(frame.time || "") ? Number(frame.time.slice(0, 2)) * 60 + Number(frame.time.slice(3, 5)) : 0;
              const diff = Math.abs(frameMinute - eventMinute);
              return diff < best.diff ? { index, diff } : best;
            }, { index: 0, diff: Infinity }).index
          : -1;
        return { event, eventIndex, frameIndex };
      });
    const dockSource = hasSnapshot && Array.isArray(live.connectors) && live.connectors.length
      ? live.connectors
      : s.dock;
    const focusedEvidence = s.evidenceFocus;
    const sharedEvidence = s.shareEvidence;
    const fallbackReading = day ? {
      title: /边界|文案|设计|spec|权限/i.test(`${day.peek || ""} ${day.narr || ""}`)
        ? "边界的编辑者"
        : /修复|根因|代码|脚本|PR/i.test(`${day.peek || ""} ${day.narr || ""}`)
          ? "根因的追问者"
          : "把一天读回来的人",
      statement: day.observation?.takeaway || day.taught || day.portrait || "看见这一天，比给它打分更重要。",
      verified: (day.events || []).slice(0, 3).map((event, index) => ({
        text: event.detail || event.io || event.title,
        receipt: event.sourceId || `${event.t || "—"} · ${event.title || `片段 ${index + 1}`}`,
      })),
      tension: "这只是今天留下的证据，不是对你的永久定义。相反的证据出现时，它也应该被改写。",
      letter: String(day.letter || "").split("\n").filter(Boolean),
    } : null;
    const dayReading = day ? (day.selfReading || fallbackReading) : null;
    const dailyCardKind = `TODAY · ${day?.short || day?.title || "REWIND"}`;
    const openDailyShare = (text, receipt, byline = "a note from today") => {
      if (!text) return;
      this.setState({
        shareFact: 97,
        shareEvidence: {
          daily: true,
          cardKind: dailyCardKind,
          title: text,
          receipt: receipt || day?.source || "Rewind · today",
          meta: `${dayReading?.title || "今天的你"} · 来自这一天的证据`,
          byline,
        },
        sfSaved: false,
      });
    };
    const dailyReadingLines = ((dayReading && dayReading.verified) || []).slice(0, 3).map((item, index) => {
      const entry = typeof item === "string" ? { text: item, receipt: "" } : item;
      const id = `reading-${index}`;
      const selected = s.dailyUnderline === id;
      return {
        text: entry.text,
        receipt: entry.receipt || `evidence ${String(index + 1).padStart(2, "0")}`,
        selected,
        decoration: selected ? "underline" : "none",
        tap: () => this.setState({ dailyUnderline: selected ? "" : id }),
        share: e => {
          e.stopPropagation();
          openDailyShare(entry.text, entry.receipt, "underlined by me · remembered by my model");
        },
      };
    });
    const rawLetterLines = Array.isArray(dayReading?.letter)
      ? dayReading.letter.filter(Boolean)
      : String(day?.letter || "").split("\n").filter(Boolean);
    const letterHasSalutation = rawLetterLines.length && /^给.+[：:]$/.test(rawLetterLines[0]);
    const dailyLetterSalutation = letterHasSalutation ? rawLetterLines[0] : "给今天的你：";
    const dailyLetterLines = (letterHasSalutation ? rawLetterLines.slice(1) : rawLetterLines).map((text, index) => {
      const id = `letter-${index}`;
      const selected = s.dailyUnderline === id;
      return {
        text,
        selected,
        decoration: selected ? "underline" : "none",
        tap: () => this.setState({ dailyUnderline: selected ? "" : id }),
        share: e => {
          e.stopPropagation();
          openDailyShare(text, day?.source || day?.title, "a letter from my personal model");
        },
      };
    });
    const dailyLetterBody = letterHasSalutation ? rawLetterLines.slice(1) : rawLetterLines;
    const dayRootText = dailyLetterBody[0] || dayReading?.statement || "";
    const dayRootDescription = dailyLetterBody[1] || "它不是对你的最终定义，只是今天愿意留在 Root 上的一句话。";
    const dayRootId = "root-letter";
    const dayRootSelected = s.dailyUnderline === dayRootId;
    const dayRootLine = {
      text: dayRootText,
      selected: dayRootSelected,
      decoration: dayRootSelected ? "underline" : "none",
      tap: () => this.setState({ dailyUnderline: dayRootSelected ? "" : dayRootId }),
      share: e => {
        e.stopPropagation();
        openDailyShare(dayRootText, day?.source || day?.title, "today's root · remembered by my model");
      },
    };
    const updateEvidence = ((dayReading && dayReading.verified) || []).map((item) =>
      typeof item === "string" ? { text: item, receipt: "" } : item
    );
    const modelUpdateRaw = dayReading ? [
      {
        kind: "FACE · 面",
        title: dayReading.title || "今天值得记住的你",
        text: dayReading.statement || "",
        receipt: updateEvidence[0]?.receipt || day?.source || "face · today",
      },
      {
        kind: "VOLUME · 体",
        title: "今天长出来的关系",
        text: dayReading.tension || updateEvidence[1]?.text || "",
        receipt: updateEvidence[1]?.receipt || day?.source || "volume · today",
      },
      {
        kind: "ROOT · 根",
        title: "根上新增的一句话",
        text: dayRootText,
        receipt: updateEvidence[2]?.receipt || day?.source || "root · today",
      },
    ].filter((item) => item.text) : [];
    const modelUpdates = modelUpdateRaw.map((item, index) => {
      const id = `model-update-${index}`;
      const selected = s.dailyUnderline === id;
      return {
        ...item,
        selected,
        decoration: selected ? "underline" : "none",
        tap: () => this.setState({ dailyUnderline: selected ? "" : id }),
        share: e => {
          e.stopPropagation();
          openDailyShare(item.text, item.receipt, `${item.kind.toLowerCase()} · updated today`);
        },
        source: e => {
          e.stopPropagation();
          this.openEvidenceSky({
            id: item.receipt,
            kind: `${item.kind} · UPDATE`,
            title: item.text,
            detail: `${item.title} · 由当天 Rewind 证据更新`,
            day: s.day,
            receipt: item.receipt,
          });
        },
      };
    });
    const identityDay = liveDays[0] || (hasSnapshot ? {
      key: "identity",
      short: "IDENTITY",
      portrait: modelIdentity.dailyLine || modelIdentity.description,
      taught: modelIdentity.dailyLine || modelIdentity.description,
      letter: modelIdentity.weeklyLetter.join("\n"),
      source: `Personal Model · ${activeModel.id}`,
      selfReading: {
        title: "今天的你",
        statement: modelIdentity.dailyLine || modelIdentity.description,
        tension: modelIdentity.description,
        letter: modelIdentity.weeklyLetter,
      },
    } : null);
    const identityReading = identityDay?.selfReading || {
      title: identityDay?.portrait || "今天的你",
      statement: identityDay?.observation?.takeaway || identityDay?.taught || identityDay?.portrait || "",
      tension: identityDay?.portrait || "",
      letter: String(identityDay?.letter || "").split("\n").filter(Boolean),
    };
    const identityDailyText = identityReading?.statement || "今天还没有足够的证据写下一句话。";
    const identityDailyId = "identity-daily";
    const identityDailySelected = s.dailyUnderline === identityDailyId;
    const identityDailyLine = {
      text: identityDailyText,
      decoration: identityDailySelected ? "underline" : "none",
      selected: identityDailySelected,
      tap: () => this.setState({ dailyUnderline: identityDailySelected ? "" : identityDailyId }),
      share: e => {
        e.stopPropagation();
        this.setState({
          shareFact: 97,
          shareEvidence: {
            daily: true,
            cardKind: `TODAY · ${identityDay?.short || "IDENTITY"}`,
            title: identityDailyText,
            receipt: identityDay?.source || "Identity · today",
            meta: `${identityReading?.title || "今天的你"} · My Page`,
            byline: "one line from my personal model",
          },
          sfSaved: false,
        });
      },
    };
    const identityThemes = (Array.isArray(live.themes) ? live.themes : [])
      .slice(0, 2)
      .map((theme) => theme.label || theme.name || theme.title)
      .filter(Boolean);
    const identityWeeklyRaw = Array.isArray(modelIdentity.weeklyLetter) && modelIdentity.weeklyLetter.length
      ? modelIdentity.weeklyLetter
      : [
          rootText,
          identityThemes.length
            ? `这一周，反复回到「${identityThemes.join("」和「")}」。`
            : modelIdentity.description,
        ].filter(Boolean);
    const identityWeeklyLines = identityWeeklyRaw.map((text, index) => {
      const id = `identity-week-${index}`;
      const selected = s.dailyUnderline === id;
      return {
        text,
        root: index === 0,
        selected,
        decoration: selected ? "underline" : "none",
        tap: () => this.setState({ dailyUnderline: selected ? "" : id }),
        share: e => {
          e.stopPropagation();
          this.setState({
            shareFact: 97,
            shareEvidence: {
              daily: true,
              cardKind: index === 0 ? "ROOT · THIS WEEK" : "LETTER · THIS WEEK",
              title: text,
              receipt: "Identity · weekly letter",
              meta: `${activeModel.displayName} · My Page · this week`,
              byline: index === 0 ? "one sentence from my root" : "underlined from my weekly letter",
            },
            sfSaved: false,
          });
        },
      };
    });
    const clipMcpText = (value, size = 118) => {
      const clean = String(value || "")
        .replace(/\s+/g, " ")
        .replace(/[�]+/g, "")
        .trim();
      return clean.length > size ? `${clean.slice(0, size - 1).trim()}…` : clean;
    };
    const readablePattern = (value) => {
      return clipMcpText(value, 220);
    };
    const currentFocus = clipMcpText(
      (live.nowItems || live.proactive || []).find((item) => item.kind === "现在" || item.kind === "present")?.title
        || live.observation
        || liveDays[0]?.events?.[0]?.title
        || "当前任务",
      48
    );
    const livePatterns = (s.persomeFaces || [])
      .slice(0, 3)
      .map((face) => ({
        text: readablePattern(face.text),
        meta: `${face.observations || "?"} 次观察 · 置信度 ${Math.round(Number(face.confidence || 0) * 100) || "?"}%`,
      }))
      .filter((pattern) => pattern.text);
    const mcpActionTitle = (event, agentName) => {
      const tool = String(event.tool || "");
      const summary = clipMcpText(event.summary, 90);
      const quoted = summary.match(/「([^」]+)」/)?.[1] || "";
      if (/behavior_patterns/i.test(tool)) return `${agentName} 读取了 ${livePatterns.length || "多"} 条行为模式`;
      if (/^search$/i.test(tool)) return `${agentName} 搜索了「${clipMcpText(quoted || summary, 56)}」`;
      if (/search_captures/i.test(tool)) return `${agentName} 回看了相关屏幕片段`;
      if (/current_context/i.test(tool)) return `${agentName} 接上了当前上下文`;
      if (/list_memories/i.test(tool)) return `${agentName} 浏览了记忆目录`;
      if (/read_memory/i.test(tool)) return `${agentName} 打开了一条已有记忆`;
      if (/get_pending_model_work/i.test(tool)) return `${agentName} 检查了尚未沉淀的记录`;
      if (/recent_activity/i.test(tool)) return `${agentName} 回顾了最近活动`;
      if (/resolve_evidence|read_receipt/i.test(tool)) return `${agentName} 追溯了一条证据`;
      return `${agentName} ${summary || `读取了 ${tool || "Personal Model"}`}`;
    };
    const mcpHowItReads = (event) => {
      const tool = String(event.tool || "");
      if (/behavior_patterns/i.test(tool)) {
        return `它把「${currentFocus}」放回长期取舍里理解：这不是一次孤立修改，而是在继续校准本地、可观察、持续生长的产品表达。`;
      }
      if (/^search$/i.test(tool)) {
        return `这次检索被放进「${currentFocus}」的背景层，用来补足问题出处，而不是只根据当前页面猜测。`;
      }
      if (/search_captures|current_context|recent_activity/i.test(tool)) {
        return `它把「${currentFocus}」识别为此刻的主线，并从最近留下的位置继续。`;
      }
      if (/read_memory|list_memories/i.test(tool)) {
        return `它先确认已有记录里真正写过什么，再决定「${currentFocus}」接下来应该怎样继续。`;
      }
      if (/resolve_evidence|read_receipt/i.test(tool)) {
        return "这次判断没有停在一句结论上；它保留了原始证据的位置，随时可以回到当时重新阅读。";
      }
      if (/get_pending_model_work/i.test(tool)) {
        return "它在区分已经成为模型理解的内容，和仍然等待沉淀的原始记录。";
      }
      return `这条读取被留在「${currentFocus}」的上下文里，之后可以从同一处继续或回溯。`;
    };
    const mappedMcpEvents = (s.mcpEvents || []).slice(0, 24).map((event) => {
      const agentName = event.agent === "codex" ? "GPT" : "Claude";
      const tool = String(event.tool || "");
      const evidence = this.evidencePool().find((item) => item.id === (event.evidenceId || event.id)) || {
        id: event.evidenceId || event.id,
        kind: `${agentName.toUpperCase()} · PERSONAL MODEL`,
        title: event.summary,
        detail: `${event.tool || "Persome"} · ${event.durationMs || 0}ms`,
        day: event.day,
        receipt: event.receipt || event.evidenceId || event.id,
      };
      const at = event.at ? new Date(event.at) : null;
      const recordedDetails = (Array.isArray(event.details) ? event.details : [])
        .map((detail) => readablePattern(detail))
        .filter(Boolean)
        .slice(0, 3);
      let detailRows = recordedDetails.map((text) => ({ text, meta: "本次调用读取" }));
      if (!detailRows.length && /behavior_patterns/i.test(tool)) {
        detailRows = livePatterns;
      } else if (!detailRows.length && event.receipt) {
        detailRows = [{
          text: /search|read_memory|list_memories/i.test(tool)
            ? "已定位到一条可回溯的记忆来源，原文仍留在 Personal Model 中。"
            : "这次读取保留了可回溯的证据位置。",
          meta: clipMcpText(event.receipt, 86),
        }];
      }
      return {
        id: event.id || event.evidenceId,
        groupKey: `${event.agent || "agent"}|${event.tool || "Persome"}|${event.summary || ""}`,
        agentId: event.agent === "codex" ? "codex" : "claude-code",
        tool,
        agentName,
        iconUrl: appIconUrl(event.agent === "codex" ? "codex" : "claude-code"),
        title: mcpActionTitle(event, agentName),
        details: detailRows,
        hasDetails: detailRows.length > 0,
        interpretation: mcpHowItReads(event),
        meta: `${event.tool || "Persome"} · ${event.durationMs || 0}ms · 本机`,
        time: at && !Number.isNaN(at.getTime()) ? at.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" }) : "",
        skyTap: e => { e.stopPropagation(); this.openEvidenceSky(evidence); },
        rewindTap: e => {
          e.stopPropagation();
          const targetDay = liveDayMap[evidence.day] ? evidence.day : latestDayKey;
          if (targetDay) {
            this.setState({ mcpOpen: false });
            this.openDay(targetDay, false);
          }
        },
      };
    });
    const seenMcpGroups = new Set();
    const mcpLiveEntries = mappedMcpEvents.filter((entry) => {
      if (seenMcpGroups.has(entry.groupKey)) return false;
      seenMcpGroups.add(entry.groupKey);
      return true;
    }).slice(0, 10);
    const targetById = Object.fromEntries((s.mcpTargets || []).map((target) => [target.id, target]));
    const mcpPersonalPassStyle = {
      position: "absolute",
      left: "5%",
      top: "41px",
      zIndex: 1,
      width: "184px",
      height: "108px",
      borderRadius: "14px",
      padding: "14px 15px",
      color: "#F5F5F4",
      background: "linear-gradient(150deg,#353539,#18181B 72%)",
      boxShadow: "inset 0 1px 0 rgba(255,255,255,.14),inset 0 0 0 .5px rgba(0,0,0,.8),0 18px 30px -18px rgba(0,0,0,.8)",
      animation: s.mcpSwiping ? "wPersonalSwipe 1.18s cubic-bezier(.45,.02,.18,1) both" : "none",
      transform: "rotate(-3deg)",
    };
    const mcpWornBadges = [
      { id: "claude-code", name: "Claude", product: "CLAUDE CODE", number: "01" },
      { id: "codex", name: "GPT", product: "CODEX", number: "02" },
    ].map((badge, index) => {
      const target = targetById[badge.id] || {};
      const worn = !!target.observed && !!s.mcpSwipeDone;
      return {
        ...badge,
        iconUrl: target.iconUrl || appIconUrl(badge.id),
        worn,
        status: s.mcpConnecting === badge.id ? "CONNECTING" : worn ? "WEARING YOUR CARD" : "WAITING",
        lanyard: worn ? "#474642" : "#C9C6BF",
        cardOpacity: worn ? 1 : .14,
        dot: s.mcpConnecting === badge.id ? "#D2A94A" : worn ? "#34C759" : "#B8B4AC",
        style: {
          position: "absolute",
          right: `${13 + (1 - index) * 104}px`,
          top: "5px",
          width: "92px",
          height: "178px",
          zIndex: 3,
          animation: worn ? `wWearBadge .55s cubic-bezier(.2,1.35,.35,1) ${index * .08}s both` : "none",
        },
      };
    });
    const mcpConnectorCards = [
      { id: "claude-code", name: "Claude", product: "Claude Code" },
      { id: "codex", name: "GPT", product: "Codex" },
    ].map((connector) => {
      const target = targetById[connector.id] || {};
      return {
        ...connector,
        iconUrl: target.iconUrl || appIconUrl(connector.id),
        status: target.observed ? "戴着你的卡" : target.installed === false ? "未发现应用" : "等待刷卡",
        dot: target.observed ? "#34C759" : "#AAA7A0",
      };
    });
    const snapshotReports = (Array.isArray(s.mcpReportsData) && s.mcpReportsData.length
      ? s.mcpReportsData
      : Array.isArray(snapshot.reports) ? snapshot.reports : [])
      .filter((report) => report.modelId === activeModel.id);
    const mcpReports = snapshotReports.length ? snapshotReports.map((report) => {
      const connector = (snapshot.connectors || []).find((item) => item.id === report.connectorId) || {};
      const open = s.mcpReportOpen === report.id;
      const sections = Array.isArray(report.sections) ? report.sections : [];
      const refs = Array.isArray(report.evidenceRefs) ? report.evidenceRefs : [];
      const points = refs.map((reference) => ({
        text: reference,
        meta: `Evidence · ${activeModel.id}`,
      }));
      const sources = refs.map((reference) => ({
        kind: "证据",
        count: 1,
        countLabel: "1 条依据",
        skyTap: () => this.openEvidenceSky(reference),
      }));
      return {
        id: report.id,
        name: connector.name || report.connectorId,
        iconUrl: connector.iconUrl || appIconUrl(report.connectorId),
        title: report.title,
        summary: report.summary,
        meta: `${report.readCount} 次读取 · ${report.evidenceCount} 条依据 · ${new Date(report.updatedAt).toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" })} 更新`,
        lead: sections.find((section) => section.kind === "lead")?.body || report.summary,
        insight: sections.find((section) => section.kind === "understanding")?.body || sections[1]?.body || report.summary,
        points,
        hasPoints: points.length > 0,
        sources,
        rows: refs.map((reference) => ({
          id: reference,
          title: reference,
          skyTap: () => this.openEvidenceSky(reference),
        })),
        hasRows: true,
        open,
        arrow: open ? "⌃" : "⌄",
        tap: e => {
          e.stopPropagation();
          this.setState({ mcpReportOpen: open ? "" : report.id });
        },
      };
    }) : [
      { id: "codex", name: "GPT", iconUrl: appIconUrl("codex"), fallbackTitle: "Personal Card · Context" },
      { id: "claude-code", name: "Claude", iconUrl: appIconUrl("claude-code"), fallbackTitle: "Current task · Context" },
    ].map((report) => {
      const rows = mcpLiveEntries.filter((entry) => entry.agentId === report.id);
      const open = s.mcpReportOpen === report.id;
      const pointKeys = new Set();
      const points = rows.flatMap((row) => row.details || []).filter((point) => {
        const key = String(point.text || "");
        if (!key || pointKeys.has(key)) return false;
        pointKeys.add(key);
        return true;
      }).slice(0, 5);
      const sourceKind = (tool) => {
        if (/behavior_patterns/.test(tool)) return "行为模式";
        if (/current_context|recent_activity|search_captures|read_recent_capture/.test(tool)) return "最近的上下文";
        if (/search|read_memory|list_memories/.test(tool)) return "相关记忆";
        if (/resolve_evidence|read_receipt/.test(tool)) return "证据原文";
        if (/get_pending_model_work/.test(tool)) return "尚未沉淀的记录";
        return "Personal Model";
      };
      const sourceMap = new Map();
      rows.forEach((row) => {
        const kind = sourceKind(row.tool || "");
        const existing = sourceMap.get(kind);
        if (existing) {
          existing.count += 1;
          if (!existing.time && row.time) existing.time = row.time;
          return;
        }
        sourceMap.set(kind, {
          kind,
          count: 1,
          time: row.time,
          skyTap: row.skyTap,
          rewindTap: row.rewindTap,
        });
      });
      const sources = [...sourceMap.values()].map((source) => ({
        ...source,
        countLabel: `${source.count} 次读取`,
      }));
      const evidenceCount = points.length;
      const insight = rows.find((row) => /behavior_patterns/.test(row.tool || ""))?.interpretation
        || rows[0]?.interpretation
        || `它把「${currentFocus}」放回你的长期上下文里理解。`;
      return {
        ...report,
        title: report.id === "codex" ? `${currentFocus} · Context` : report.fallbackTitle,
        summary: rows.length
          ? `${report.name} 已把本次读取整理成一页可以继续使用的上下文。`
          : `${report.name} 第一次读取你的卡后，会在这里写下一页。`,
        meta: rows.length
          ? `${rows.length} 次读取 · ${evidenceCount || "可回溯"} 条依据 · ${rows[0]?.time || "刚刚"} 更新`
          : "等待第一份页面",
        lead: `围绕「${currentFocus}」，${report.name} 把刚才的上下文、相关记忆与长期理解收进了同一页。现在可以从这里继续，不必重新解释。`,
        insight,
        points,
        hasPoints: points.length > 0,
        sources,
        rows,
        hasRows: rows.length > 0,
        open,
        arrow: open ? "⌃" : "⌄",
        tap: e => {
          e.stopPropagation();
          this.setState({ mcpReportOpen: open ? "" : report.id });
        },
      };
    }).filter((report) => report.hasRows);
    const pill = on => ({
      fontSize: "13px", padding: "8px 22px", borderRadius: "99px", cursor: "pointer", userSelect: "none",
      background: on ? "#1D1D1F" : "#FFFFFF", color: on ? "#FFFFFF" : "#1D1D1F",
      boxShadow: on ? "0 6px 18px -6px rgba(0,0,0,.35)" : "0 0 0 1px #E7E4DE,0 2px 8px -2px rgba(0,0,0,.08)",
      fontWeight: 550, letterSpacing: "-.01em", transition: "transform .15s"
    });

    return {
      setupRequired: !!s.setupRequired || !hasSnapshot,
      setupLoading: !!s.setupLoading,
      setupNeedsProfile: !s.setupLoading && !s.setupStatus?.profile,
      setupHasProfile: !!s.setupStatus?.profile,
      setupNeedsRuntime: !s.setupLoading && !s.setupStatus?.ready,
      setupProfileName: s.setupStatus?.profile?.displayName || "",
      setupProfileHandle: s.setupStatus?.profile?.handle || "",
      setupStateLabel: s.setupStatus?.state === "not_installed"
        ? "Personal Model 尚未安装"
        : s.setupStatus?.state === "onboarding_required"
          ? "等待完成 macOS 权限与初始化"
          : s.setupStatus?.state === "runtime_unavailable"
            ? "本机 Personal Model 暂时不可用"
            : s.setupStatus?.state === "profile_required"
              ? "先创建你的 Personal Card"
              : "正在检测这台 Mac",
      setupErrorOn: !!s.setupError,
      setupError: s.setupError || "",
      setupMessageOn: !!s.setupMessage,
      setupMessage: s.setupMessage || "",
      setupSaveProfile: () => this.saveSetupProfile(),
      setupLaunchRuntime: () => this.launchPersonalModelSetup(),
      setupRefresh: () => this.refreshSetup(),
      setupButtonLabel: s.setupLoading ? "正在处理…" : "安装 / 完成本机授权",
      modelId: activeModel.id,
      modelDisplayName: activeModel.displayName,
      modelHandle: activeModel.handle,
      modelMemberNumber: activeModel.memberNumber,
      modelMemberLabel: `№ ${activeModel.memberNumber}`,
      modelMemberCompact: `№${activeModel.memberNumber}`,
      modelSinceYear: String(activeModel.sinceYear),
      modelTagline: modelCard.tagline,
      modelPublicUrl: modelCard.publicUrl,
      modelIdentityDescription: modelIdentity.description,
      modelIdentityLine: modelIdentity.dailyLine || modelIdentity.description,
      modelShareDoing: snapshot?.personalModel?.root || modelIdentity.description,
      modelShareThinking: modelIdentity.dailyLine || modelCard.tagline,
      modelIdentitySpace: `${activeModel.displayName}'s space`,
      modelMemoryNext: String((Number(snapshot?.personalModel?.memoryCount) || 0) + 1),
      modelAuthorizationMode: modelAuthorization.viewerMode,
      devSwitcher: !!s.devSwitcher,
      devModelOptions: (s.modelOptions || []).map((model) => ({
        id: model.id,
        label: `${model.displayName} · ${model.handle}`,
        active: model.id === activeModel.id,
        dot: model.id === activeModel.id ? "#34C759" : "rgba(255,255,255,.28)",
        tap: () => {
          if (model.id === activeModel.id || s.loadingModelId) return;
          this.switchModel(model.id, {
            access: model.id === s.ownerModelId ? "owner" : "authorized",
          }).catch(() => {});
        },
      })),
      canSearch: modelScopes.has("model:search"),
      canAsk: modelScopes.has("model:ask"),
      canCorrect: modelScopes.has("model:correct"),
      canRewind: modelScopes.has("rewind:read"),
      canEvidence: modelScopes.has("evidence:read"),
      canReports: modelScopes.has("reports:read"),
      canConnectors: modelScopes.has("connectors:read"),
      canConnect: modelScopes.has("connectors:connect"),
      visitorAskOn: s.visitor && modelScopes.has("model:ask"),
      opening: s.opening && hasSnapshot,
      openCard: () => { if (!s.openingOpen) this.setState({ openingOpen: true }, () => setTimeout(() => this.setState({ opening: false }), 1150)); },
      openingStyle: { position: "fixed", inset: 0, zIndex: 100, background: "#F1EFE9", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", cursor: "pointer", opacity: s.openingOpen ? 0 : 1, transition: "opacity .8s ease .35s" },
      dossierStyle: { position: "relative", width: "290px", height: "388px", transformStyle: "preserve-3d", transform: s.openingOpen ? "rotateX(2deg) rotateY(0)" : "rotateX(7deg) rotateY(-13deg)", transition: "transform 1.1s cubic-bezier(.34,1.2,.4,1)" },
      coverFace: Object.assign({ position: "absolute", inset: 0, zIndex: 3, borderRadius: "16px", transformOrigin: "left center", backfaceVisibility: "hidden", transform: s.openingOpen ? "rotateY(-164deg)" : "none", transition: "transform 1.3s cubic-bezier(.5,.05,.2,1)", display: "flex", flexDirection: "column", justifyContent: "space-between", padding: "26px" }, mat.face),
      innerCard: { position: "absolute", inset: "14px", zIndex: 1, background: "#FEFEFD", borderRadius: "12px", boxShadow: "0 20px 50px rgba(0,0,0,.16)", border: "1px solid #ECECEA", display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", gap: "10px", padding: "26px", textAlign: "center", transform: s.openingOpen ? "translateY(-24px) scale(1.04)" : "none", transition: "transform 1s cubic-bezier(.34,1.1,.35,1) .5s" },
      glyphPlain: activeGlyph.map(p => ({ bg: p ? "#F5F5F4" : "#2C2C2E" })),

      isHome: s.view === "home" || s.view === "share", isYear: s.view === "year", isMonth: s.view === "month", isDay: s.view === "day",
      isSky: s.view === "sky",
      isIdentity: s.view === "identity",
      notHome: s.view === "year" || s.view === "month" || s.view === "day" || s.view === "sky" || s.view === "identity",
      goSkyStop: e => { if (!modelScopes.has("evidence:read")) return; e.stopPropagation(); this.setState({ view: "sky", starRead: -1, skySel: -1, skyFocus: -1, evidenceFocus: null, menuOn: false, dockOpen: false }); },
      menuSky: () => { if (modelScopes.has("evidence:read")) this.setState({ menuOn: false, view: "sky", starRead: -1, skySel: -1, skyFocus: -1, evidenceFocus: null, dockOpen: false }); },
      dropSky: () => { if (modelScopes.has("evidence:read")) this.setState({ view: "sky", starRead: -1, skySel: -1, skyFocus: -1, evidenceFocus: null, askDrop: false, dockOpen: false }); },
      skyBgTap: () => this.setState({ starRead: -1, skySel: -1, skyFocus: -1, evidenceFocus: null }),
      skyModes: [["星座", "constellation"], ["星尘", "dust"], ["时间", "time"]].map(([t, m]) => ({
        t, tap: () => this.setState({ skyMode: m }),
        style: { fontSize: "11.5px", padding: "5px 16px", borderRadius: "99px", cursor: "pointer", userSelect: "none", transition: "background .2s, color .2s", color: (s.skyMode || "constellation") === m ? "#0B0B0D" : "rgba(255,255,255,.6)", background: (s.skyMode || "constellation") === m ? "#F5F5F4" : "transparent", fontWeight: (s.skyMode || "constellation") === m ? 600 : 400 }
      })),
      skyLegend: (s.skyMode || "constellation") === "dust" ? "只看密度 — 颜色是主题,哪里亮,日子就长在哪里" : s.skyMode === "time" ? "由内向外 = 从这周到半年前 · 新记忆亮,旧记忆暗" : "星 = 记忆段 · 线 = 同一件事 · 星座 = 主题",
      skyStars: (() => {
        const mode = s.skyMode || "constellation";
        const d = this.skyData();
        const foc = s.skyFocus != null ? s.skyFocus : -1;
        const out = d.stars.map((st, idx) => {
          const x = mode === "time" ? st.tx : st.x, y = mode === "time" ? st.ty : st.y;
          const rec = 1 - st.age / 28;
          const cc = st.ti >= 0 ? d.themes[st.ti].cc : "235,238,250";
          const dimmed = foc >= 0 && st.ti !== foc;
          const move = "left .9s cubic-bezier(.4,0,.2,1), top .9s cubic-bezier(.4,0,.2,1), opacity .5s";
          if (!st.bright) return { tap: null, style: { position: "absolute", left: x + "%", top: y + "%", width: (st.dim ? 1.3 : 2) + "px", height: (st.dim ? 1.3 : 2) + "px", borderRadius: "50%", background: "rgba(" + cc + "," + (st.dim ? ".3" : (.4 + rec * .5).toFixed(2)) + ")", opacity: dimmed ? .15 : 1, transition: move } };
          const sel = s.skySel === idx;
          return { tap: e => { e.stopPropagation(); this.setState({ starRead: st.fi, skySel: idx, skyFocus: st.ti, starFixing: false, evidenceFocus: st.evidence || null }); },
            style: { position: "absolute", left: x + "%", top: y + "%", width: "22px", height: "22px", marginLeft: "-11px", marginTop: "-11px", borderRadius: "50%", cursor: "pointer", zIndex: 2,
              background: "radial-gradient(circle, rgba(" + cc + "," + (.6 + rec * .4).toFixed(2) + ") 0 " + (st.big ? 2.6 : 1.9) + "px, rgba(" + cc + ",.42) " + (st.big ? 3.8 : 2.9) + "px, rgba(" + cc + ",.1) 6.5px, transparent 10px)",
              boxShadow: sel ? "inset 0 0 0 1px rgba(" + cc + ",.7), 0 0 20px 4px rgba(" + cc + ",.4)" : "none",
              opacity: dimmed ? .18 : 1,
              animation: st.big ? "wPulse 4s ease-in-out infinite" : "none",
              transition: move + ", box-shadow .25s" } };
        });
        out.push({ tap: e => { e.stopPropagation(); this.setState({ starRead: 99, skySel: -2, skyFocus: -1, starFixing: false, evidenceFocus: null }); },
          style: { position: "absolute", left: "50%", top: mode === "time" ? "46%" : "45%", width: "30px", height: "30px", marginLeft: "-15px", marginTop: "-15px", borderRadius: "50%", cursor: "pointer", zIndex: 3,
            background: "radial-gradient(circle, #FFFFFF 0 3px, rgba(200,210,255,.5) 5px, rgba(200,210,255,.14) 9px, transparent 14px)",
            boxShadow: s.starRead === 99 ? "0 0 24px 5px rgba(200,210,255,.4)" : "none",
            animation: "wPulse 3.5s ease-in-out infinite", transition: "top .9s cubic-bezier(.4,0,.2,1)" } });
        return out;
      })(),
      skyEdges: (() => {
        const mode = s.skyMode || "constellation";
        const d = this.skyData();
        const foc = s.skyFocus != null ? s.skyFocus : -1;
        return d.edges.map(ed => {
          const A = ed.a < 0 ? { x: 50, y: 45 } : d.stars[ed.a], B = d.stars[ed.b];
          const cc = d.themes[ed.ti].cc;
          const hot = foc === ed.ti;
          return { x1: A.x, y1: A.y * .62, x2: B.x, y2: B.y * .62, w: ed.a < 0 ? .1 : (hot ? .26 : .16),
            stroke: "rgba(" + cc + "," + (hot ? .85 : (foc >= 0 ? .05 : .3)) + ")",
            style: { opacity: mode === "constellation" ? 1 : 0, transition: "opacity .7s" } };
        });
      })(),
      skyMist: (s.skyMode || "constellation") === "time" ? [] : this.skyData().themes.map((t, i) => ({
        style: { position: "absolute", left: t.x + "%", top: t.y + "%", width: (t.s * 14 + 90) + "px", height: (t.s * 10 + 70) + "px", transform: "translate(-50%,-50%)", borderRadius: "50%", pointerEvents: "none",
          background: "radial-gradient(closest-side, rgba(" + t.cc + ",.13), transparent 70%)", filter: "blur(6px)",
          animation: "wDrift " + (11 + i * 2) + "s ease-in-out " + (i * .9) + "s infinite" }
      })),
      skyLabels: this.skyData().labels.map((l, i) => ({
        name: l.n, sub: l.sub, tap: () => this.openDay(l.day, false),
        style: { position: "absolute", left: l.x + "%", top: l.y + "%", transform: "translate(-50%,-50%)", zIndex: 4, textAlign: "center", cursor: "pointer", display: "flex", flexDirection: "column", gap: "2px", opacity: (s.skyMode || "constellation") === "constellation" ? ((s.skyFocus != null && s.skyFocus >= 0 && s.skyFocus !== i) ? .15 : 1) : 0, pointerEvents: (s.skyMode || "constellation") === "constellation" ? "auto" : "none", transition: "opacity .5s" },
        nameStyle: { fontSize: "12.5px", fontWeight: 600, letterSpacing: ".02em", color: "rgb(" + this.skyData().themes[i].cc + ")", textShadow: "0 1px 10px rgba(0,0,0,.9)" },
        subStyle: { fontFamily: "'SF Mono',ui-monospace,Menlo,monospace", fontSize: "8.5px", color: "rgba(232,234,245,.45)", letterSpacing: ".08em" }
      })),
      proBriefOn: hasSnapshot && !s.visitor && s.view === "home" && (this.props.proactiveStyle ?? "briefing") === "briefing",
      proPushOn: hasSnapshot && !s.visitor && s.view === "home" && (this.props.proactiveStyle ?? "briefing") === "push",
      proHeadline: "Now",
      proWhisper: "过去 · 现在 · 未来",
      proDateLabel: hasSnapshot ? (live.proactiveLabel || "").replace(/\s*·\s*LIVE$/i, "") : "",
      proItems: hasSnapshot && Array.isArray(live.nowItems) && live.nowItems.length
        ? live.nowItems.slice(0, 3).map(item => ({
              kind: item.kind === "回溯" ? "过去" : item.kind === "继续" ? "现在" : item.kind,
              marker: item.kind === "过去" || item.kind === "回溯" ? "↶" : item.kind === "现在" || item.kind === "继续" ? "—" : "○",
              iconUrl: appIconUrl(item.app || item.title),
              t: item.t,
              title: item.title,
              why: item.why,
              rowStyle: { display: "grid", gridTemplateColumns: "34px 48px minmax(0,1fr) auto", gap: "10px", alignItems: "center", padding: "12px 2px", borderTop: "1px solid rgba(60,60,67,.10)", cursor: "pointer", opacity: item.kind === "未来" ? .76 : 1 },
              tap: () => this.openDay(item.day, false)
            }))
        : [],
      proOpen: () => futureEvents.length ? this.openDay(futureEvents[0].day, false) : latestDayKey ? this.openDay(latestDayKey, false) : null,
      proCal: () => this.setState({ view: "month", rw: "cal" }),
      proFoot: "不是待办，只是时间留下的线索",
      proMoreT: "时间",
      proOpenT: "看看明天",
      spotlightPh: s.ph || "搜索你记得的事…",
      spotlightSky: () => { if (modelScopes.has("evidence:read")) this.setState({ view: "sky", starRead: -1, skySel: -1, skyFocus: -1, evidenceFocus: null }); },
      spotlightMcp: () => this.openMcp(),
      proPushes: hasSnapshot && Array.isArray(live.pushes) && live.pushes.length ? live.pushes.map(p => ({
        text: p.text, sub: p.sub, delay: p.delay || ".15s", tap: () => this.openDay(p.day, false)
      })) : [
        { text: "Personal Model 正在等待新的个人活动片段。", sub: "只会显示这台 Mac 上属于你的内容", delay: ".15s", tap: () => {} }
      ],
      menuOn: !!s.menuOn,
      menuToggle: () => this.setState({ menuOn: !s.menuOn }),
      menuBtn: { cursor: "pointer", display: "inline-grid", placeItems: "center", width: "26px", height: "20px", borderRadius: "5px", color: "#1D1D1F", background: s.menuOn ? "rgba(0,0,0,.14)" : "transparent" },
      menuSearch: () => { if (modelScopes.has("model:search")) this.setState({ menuOn: false, view: "home", dockOpen: false }, () => setTimeout(() => { const el = document.querySelector("[data-spotlight-input]"); if (el) el.focus(); }, 60)); },
      menuAsk: () => { if (modelScopes.has("model:ask")) this.setState({ menuOn: false, view: "home", askOpen: true, dockOpen: false }); },
      menuRemember: () => { if (modelScopes.has("rewind:read")) this.setState({ menuOn: false, view: "month", dockOpen: false }); },
      menuWork: () => { if (modelScopes.has("connectors:read")) { this.setState({ menuOn: false, view: "home" }); this.openMcp(); } },
      menuShare: () => this.setState({ menuOn: false, view: "share", dockOpen: false, copied: false }),
      menuSpeak: () => this.switchModel(activeModel.id, { access: s.visitor ? (activeModel.id === s.ownerModelId ? "owner" : "authorized") : "public" }).catch(() => {}),
      menuSpeakT: s.visitor ? "回到 owner 视角" : "以访客身份看这张卡",
      menuPause: () => this.setState({ recPaused: !s.recPaused }),
      recDot: s.recPaused ? "#8E8E93" : "#34C759",
      recT: s.recPaused ? "已暂停 · 点击恢复记录" : "正在记录 · 暂停 1 小时",
      persomeRefresh: () => this.loadPersome(),
      persomeBadge: s.switchError ? "Persome · 切换失败" : s.persomeLoading ? "Persome · 连接中" : s.persomeConnected ? "Persome · 已连接" : "Persome · 离线",
      persomeBadgeTitle: s.switchError || (s.persomeConnected ? "本机 Personal Model · " + countText + " 条记忆 · 点击刷新" : (s.persomeError || "点击重新连接")),
      persomeDot: s.switchError ? "#FF453A" : s.persomeLoading ? "#FF9F0A" : s.persomeConnected ? "#34C759" : "#8E8E93",
      persomeSyncLabel: s.persomeConnected ? "实时接入" : "等待本机模型",
      persomeRebuildT: s.persomeConnected ? "LIVE · 本机模型" : "尚未连接",
      mcpOpen: !!s.mcpOpen,
      mcpLoading: !!s.mcpLoading,
      mcpErrorOn: !!s.mcpError,
      mcpError: s.mcpError || "",
      mcpClose: () => this.setState({ mcpOpen: false, mcpConnectorPicker: false }),
      mcpStop: e => e.stopPropagation(),
      mcpRefresh: () => this.loadMcp(),
      mcpSwipe: () => this.swipeMcpCard(),
      mcpSwiping: !!s.mcpSwiping,
      mcpSwipeDone: !!s.mcpSwipeDone,
      mcpAllConnected: (s.mcpTargets || []).length > 0 && (s.mcpTargets || []).every((target) => target.observed),
      mcpSwipeLabel: s.mcpSwiping ? "正在刷卡…" : s.mcpSwipeDone ? "Claude 与 GPT 已戴上你的卡" : "Swipe your Personal Card",
      mcpSwipeHint: s.mcpSwiping
        ? `正在把 ${activeModel.handle} 交给新的协作者`
        : s.mcpSwipeDone
          ? "它们现在带着同一份你继续工作"
          : "刷一下，让 Agent 戴上你的工牌",
      mcpPersonalPassStyle,
      mcpWornBadges,
      mcpReaderDot: s.mcpSwiping ? "#D2A94A" : s.mcpSwipeDone ? "#34C759" : "#8E8E93",
      mcpHasTargets: (s.mcpTargets || []).length > 0,
      mcpConnectorCards,
      mcpConnectorPickerOn: !!s.mcpConnectorPicker,
      mcpConnectorPickerToggle: e => {
        e.stopPropagation();
        this.setState({ mcpConnectorPicker: !s.mcpConnectorPicker });
      },
      mcpConnectorOptions: [
        { name: "Cursor", sub: "MCP connector", glyph: "◩" },
        { name: "Gemini", sub: "MCP connector", glyph: "✦" },
        { name: "Other Agent", sub: "Bring your own MCP client", glyph: "＋" },
      ],
      mcpTargets: (s.mcpTargets || []).map((target) => ({
        name: target.id === "codex" ? "GPT" : "Claude",
        product: target.id === "codex" ? "via Codex" : "via Claude Code",
        iconUrl: target.iconUrl,
        status: s.mcpConnecting === target.id ? "正在连接" : target.observed ? "已连接" : target.installed ? "等待刷卡" : "未发现应用",
        statusColor: target.observed ? "#237A45" : target.installed ? "#8A8780" : "#A16256",
        dot: target.observed ? "#34C759" : target.installed ? "#B7B3AB" : "#C88778"
      })),
      mcpHasEvents: (s.mcpEvents || []).length > 0,
      mcpNoEvents: !s.mcpLoading && (s.mcpEvents || []).length === 0,
      mcpLiveEntries,
      mcpLiveEmpty: !s.mcpLoading && mcpLiveEntries.length === 0,
      mcpLiveDate: new Date().toLocaleDateString("zh-CN", { month: "long", day: "numeric", weekday: "long" }),
      mcpReports,
      mcpHasReports: mcpReports.length > 0,
      mcpNoReports: !s.mcpLoading && mcpReports.length === 0,
      clockLabel: hasSnapshot && live.clockLabel ? live.clockLabel : "as of now",
      cardMonthYear: modelCard.monthYear,
      monthLabel: hasSnapshot ? (live.monthLabel || String(modelCard.monthYear || "").split("/")[0].trim()) : "",
      yearLabel: hasSnapshot ? (live.yearLabel || String(modelCard.monthYear || "").split("/")[1]?.trim() || "") : "",
      graphLabel: hasSnapshot ? ((live.monthLabel || "PERSONAL MODEL").toUpperCase() + " · " + ((live.themes || []).length || 0) + " live themes") : "",
      mRemember: () => { if (modelScopes.has("rewind:read")) this.setState({ view: "month", dockOpen: false }); },
      mWork: () => { if (modelScopes.has("connectors:read")) { this.setState({ view: "home" }); this.openMcp(); } },
      mSpeak: () => this.switchModel(activeModel.id, { access: s.visitor ? (activeModel.id === s.ownerModelId ? "owner" : "authorized") : "public" }).catch(() => {}),
      cardOrder: s.visitor ? 3 : 1,
      askOrder: s.visitor ? 2 : 3,
      askMt: s.visitor ? "10px" : "32px",
      heroLineOn: hasSnapshot && !s.visitor && s.view === "home" && !s.dockOpen,
      heroLineText: hasSnapshot ? "今天 · Persome 记录了 " + ((liveDays[0] && liveDays[0].events || []).length || 0) + " 个实时活动段" : "",
      heroLineTap: () => this.setState({ dockOpen: true, revIdx: -1 }),
      isShare: s.view === "share",
      closeShare: () => this.setState({ view: "home" }),
      openIdentity: () => { if (modelScopes.has("identity:read")) this.setState({ view: "identity", dailyUnderline: "" }); },
      identityBack: () => this.setState({ view: "share", dailyUnderline: "" }),
      identityClose: () => this.setState({ view: "home", dailyUnderline: "" }),
      identityUpdated: hasSnapshot ? (live.clockLabel || "as of now") : "",
      identityOnline: s.persomeConnected ? "model online" : hasSnapshot ? "offline snapshot" : "model unavailable",
      identityGlyph: activeGlyph.map(p => ({ bg: p ? "#F5F5F4" : "#343438" })),
      identityDailyTitle: identityReading?.title || "今天的你",
      identityDailyLine,
      identityWeekLabel: "AUG 3 — AUG 9",
      identityWeeklyLines,
      shareTargets: [["𝕏","X"],["in","LinkedIn"],["♥","Tinder"],["Ig","Instagram"],["♫","Spotify"]].map(([icon, name]) => ({ icon, name })),
      copyT: s.copied ? "已复制" : `复制 ${modelCard.publicUrl}`,
      copyLink: () => this.setState({ copied: true }),
      shareDust: Array.from({ length: 46 }, (_, i) => ({ style: {
        position: "absolute", borderRadius: "50%",
        width: (i % 3 === 0 ? 2 : 1.3) + "px", height: (i % 3 === 0 ? 2 : 1.3) + "px",
        left: ((i * 137) % 97 + 1.5) + "%", top: ((i * 89) % 93 + 3) + "%",
        background: "rgba(255,255,255," + (i % 4 === 0 ? .5 : .22) + ")",
        animation: i % 5 === 0 ? "wPulse " + (3 + i % 4) + "s ease-in-out " + (i % 6) / 2 + "s infinite" : "none"
      } })),
      goHome: () => this.setState({ view: "home", day: null }),
      visitor: s.visitor, owner: !s.visitor,
      visitorT: s.visitor ? "← owner 视角" : "以访客身份看 →",
      toggleVisitor: () => this.switchModel(activeModel.id, { access: s.visitor ? (activeModel.id === s.ownerModelId ? "owner" : "authorized") : "public" }).catch(() => {}),

      flip: () => { if (modelScopes.has("evidence:read")) this.setState({ flipped: !s.flipped }); },
      heroWrap: { position: "relative", width: "min(430px,80vw)", aspectRatio: "1.586", transformStyle: "preserve-3d", cursor: "pointer", transition: "transform .9s cubic-bezier(.4,.1,.2,1)",
        transform: (s.flipped ? "rotateY(180deg)" : "rotateY(0)") + (s.dockOpen ? " scale(.88) translateY(-8px)" : "") + (s.hoverCard ? " rotateY(" + ((s.cx - .5) * 6).toFixed(1) + "deg) rotateX(" + ((.5 - s.cy) * 5).toFixed(1) + "deg)" : ""),
        filter: s.flying ? "brightness(.96)" : "none" },
      cardMove: e => {
        const r = e.currentTarget.getBoundingClientRect();
        this.setState({ cx: (e.clientX - r.left) / r.width, cy: (e.clientY - r.top) / r.height, hoverCard: true });
      },
      cardLeave: () => this.setState({ hoverCard: false }),
      glare: { position: "absolute", inset: 0, borderRadius: "20px", pointerEvents: "none", zIndex: 2,
        background: "radial-gradient(60% 90% at " + ((s.cx || .3) * 100).toFixed(0) + "% " + ((s.cy || .2) * 100).toFixed(0) + "%, rgba(255,255,255,.13), transparent 60%)",
        opacity: s.hoverCard && !s.flipped ? 1 : 0, transition: "opacity .4s" },
      heroFront: Object.assign({ position: "absolute", inset: 0, borderRadius: "20px", backfaceVisibility: "hidden", padding: "24px 30px", visibility: s.flipped ? "hidden" : "visible", transition: "visibility 0s .22s" }, mat.face),
      matCorner: mat.corner, matDetail: mat.detail,
      sharePosterStyle: Object.assign({}, mat.face, { width: "min(320px,86vw)", aspectRatio: ".68", borderRadius: "18px", padding: "26px 28px 22px", position: "relative", textAlign: "left", display: "flex", flexDirection: "column", boxShadow: "0 60px 130px -30px rgba(0,0,0,.75)" }),
      shareLine: mat.ink ? "rgba(0,0,0,.12)" : "rgba(255,255,255,.14)",
      shareNameStyle: Object.assign({ fontSize: "21px", fontWeight: 550, letterSpacing: ".085em", fontFamily: "-apple-system,BlinkMacSystemFont,'SF Pro Display','Helvetica Neue',sans-serif" }, mat.name),
      nameStyle: Object.assign({ fontSize: "34px", fontWeight: 550, letterSpacing: ".085em", fontFamily: "-apple-system,BlinkMacSystemFont,'SF Pro Display','Helvetica Neue',sans-serif" }, mat.name),
      nameStyleSm: Object.assign({ fontSize: "28px", fontWeight: 550, letterSpacing: ".085em", fontFamily: "-apple-system,BlinkMacSystemFont,'SF Pro Display','Helvetica Neue',sans-serif" }, mat.name),
      shareCardStyle: Object.assign({ width: "min(340px,100%)", aspectRatio: "1.586", margin: "0 auto", borderRadius: "16px", padding: "18px 22px", position: "relative", textAlign: "left" }, mat.face, { boxShadow: mat.face.boxShadow.replace("44px 90px -24px", "34px 70px -20px") }),
      heroBack: Object.assign({ position: "absolute", inset: 0, borderRadius: "20px", backfaceVisibility: "hidden", transform: "rotateY(180deg)", padding: "26px 30px", fontFamily: "-apple-system,BlinkMacSystemFont,'SF Pro Display','Helvetica Neue',sans-serif", visibility: s.flipped ? "visible" : "hidden", transition: "visibility 0s .22s" }, mat.face),
      backStrong: mat.ink ? "#57544E" : "#F5F5F4",
      glyphHero: activeGlyph.map(p => ({ bg: p ? mat.pxOn : mat.pxOff, anim: "none" })),
      stars: (this.props.firstRun ? [] : this.stars()).map((st, i) => {
        const bright = st.style.boxShadow !== "none";
        const fi = bright ? i % liveFacts.length : -1;
        if (!bright) return { style: mat.ink ? Object.assign({}, st.style, { background: st.style.background.replace("245,245,244", "70,66,58") }) : st.style, tap: null };
        const blue = st.style.background === "#8FA6FF";
        const c = blue ? (mat.ink ? "51,80,240" : "143,166,255") : (mat.ink ? "70,66,58" : "245,245,244");
        const sel = s.starRead === fi;
        return {
          style: Object.assign({}, st.style, {
            cursor: "pointer", width: "20px", height: "20px", borderRadius: "50%",
            transform: "translate(-7px,-7px)",
            background: "radial-gradient(circle, rgb(" + c + ") 0 1.8px, rgba(" + c + ",.42) 2.8px, rgba(" + c + ",.1) 6px, transparent 9px)",
            boxShadow: sel ? "inset 0 0 0 1px rgba(" + c + ",.55), 0 0 14px 2px rgba(" + c + ",.35)" : "none",
            transition: "box-shadow .25s"
          }),
          tap: e => { e.stopPropagation(); this.setState({ starRead: fi, starFixing: false, guideDone: true }); }
        };
      }),
      starReadOff: s.starRead < 0,
      memCount: this.props.firstRun ? "DAY 0" : countText,
      guideOn: s.flipped && s.starRead < 0 && !s.guideDone,
      rootTap: e => { e.stopPropagation(); this.setState({ starRead: 99, starFixing: false, guideDone: true }); },
      rootColor: mat.ink ? "#3350F0" : "#8FA6FF",
      starReadOn: s.starRead >= 0,
      popStyle: { position: "absolute", left: "18px", right: "18px", bottom: "18px", zIndex: 5, borderRadius: "11px", padding: "12px 14px", backdropFilter: "blur(8px)", animation: "wFade .25s ease", cursor: "default",
        background: mat.ink ? "rgba(255,255,255,.94)" : "rgba(10,10,12,.94)",
        border: mat.ink ? "1px solid rgba(0,0,0,.08)" : "1px solid rgba(255,255,255,.1)",
        boxShadow: mat.ink ? "0 10px 30px -10px rgba(0,0,0,.2)" : "0 10px 30px -10px rgba(0,0,0,.6)" },
      popText: mat.ink ? "#3B3833" : "#F5F5F4",
      popInput: { width: "100%", borderRadius: "6px", padding: "6px 10px", fontSize: "11.5px", outline: "none", marginTop: "9px",
        border: mat.ink ? "1px solid rgba(0,0,0,.14)" : "1px solid rgba(255,255,255,.14)",
        background: mat.ink ? "rgba(0,0,0,.03)" : "rgba(255,255,255,.05)",
        color: mat.ink ? "#3B3833" : "#F5F5F4" },
      starKind: focusedEvidence ? focusedEvidence.kind : s.starRead === 99 ? "ROOT · 我是谁" : s.starRead >= 0 ? liveFacts[s.starRead].k : "",
      starKindStyle: { fontSize: "8.5px", letterSpacing: ".08em", padding: "1px 6px", borderRadius: "3px", whiteSpace: "nowrap", color: mat.ink ? "#3350F0" : "#B9C6FF", border: "1px solid " + (mat.ink ? "rgba(51,80,240,.3)" : "rgba(143,166,255,.32)") },
      starText: focusedEvidence ? `${focusedEvidence.title}${focusedEvidence.detail ? "。 " + focusedEvidence.detail : ""}` : s.starRead === 99 ? ((s.factFixes || {})[99] || (this.props.firstRun ? "我还不认识你。今晚起，我陪你过每一天——这颗星会开始有内容。" : rootText)) : s.starRead >= 0 ? ((s.factFixes || {})[s.starRead] || liveFacts[s.starRead].t) : "",
      starReceipt: focusedEvidence ? focusedEvidence.receipt : s.starRead === 99 ? (this.props.firstRun ? "root_1 · day 0" : "root_live · Persome · 由全部 " + countText + " 条记忆推出") : s.starRead >= 0 ? liveFacts[s.starRead].r : "",
      popRule: mat.ink ? "rgba(0,0,0,.08)" : "rgba(255,255,255,.1)",
      starShare: e => { e.stopPropagation(); this.setState({ shareFact: focusedEvidence ? 98 : s.starRead, shareEvidence: focusedEvidence || null, sfSaved: false }); },
      sfOn: s.shareFact != null && s.shareFact >= 0,
      sfKind: sharedEvidence ? (sharedEvidence.cardKind || "EVIDENCE") : s.shareFact === 99 ? "ROOT" : s.shareFact >= 0 ? (liveFacts[s.shareFact].k === "画像" ? "FACE" : liveFacts[s.shareFact].k === "习惯" ? "PATTERN" : "MEMORY") : "",
      sfText: sharedEvidence ? sharedEvidence.title : s.shareFact === 99 ? ((s.factFixes || {})[99] || rootText) : s.shareFact >= 0 ? ((s.factFixes || {})[s.shareFact] || liveFacts[s.shareFact].t) : "",
      sfMeta: sharedEvidence ? (sharedEvidence.meta || `${sharedEvidence.receipt} · 来自 Personal Model 证据链`) : s.shareFact === 99 ? "root_live · 由全部 " + countText + " 条记忆推出" : s.shareFact >= 0 ? liveFacts[s.shareFact].r + " · " + liveFacts[s.shareFact].f : "",
      sfByline: sharedEvidence?.byline || "personal model said this",
      sfDaily: !!sharedEvidence?.daily,
      sfGlyph: activeGlyph.map(p => ({ bg: p ? "#2E2B26" : "rgba(0,0,0,.07)" })),
      sfClose: () => this.setState({ shareFact: -1, shareEvidence: null }),
      sfStop: e => e.stopPropagation(),
      sfSaveT: s.sfSaved ? "已存 · 去发吧" : "保存图片",
      sfSave: () => this.saveShareImage(
        sharedEvidence ? (sharedEvidence.cardKind || "EVIDENCE") : s.shareFact === 99 ? "ROOT" : "MEMORY",
        sharedEvidence ? sharedEvidence.title : s.shareFact === 99 ? ((s.factFixes || {})[99] || rootText) : s.shareFact >= 0 ? ((s.factFixes || {})[s.shareFact] || liveFacts[s.shareFact].t) : "",
        sharedEvidence ? (sharedEvidence.meta || sharedEvidence.receipt || "") : s.shareFact === 99 ? "root_live · 由全部 " + countText + " 条记忆推出" : s.shareFact >= 0 ? liveFacts[s.shareFact].r + " · " + liveFacts[s.shareFact].f : "",
        sharedEvidence?.byline || "personal model said this",
      ),
      starFresh: focusedEvidence ? "真实事件 · 可回溯" : s.starRead === 99 ? (hasSnapshot ? "Persome · 当前快照" : "等待 Personal Model") : s.starRead >= 0 ? liveFacts[s.starRead].f : "",
      starSource: e => { e.stopPropagation(); const requestedDay = focusedEvidence?.day || (s.starRead === 99 ? latestDayKey : liveFacts[s.starRead].day); const d = liveDayMap[requestedDay] ? requestedDay : latestDayKey; this.setState({ flipped: false, starRead: -1, evidenceFocus: null }); if (d) this.openDay(d, false); },
      starAct: e => { e.stopPropagation(); this.openMcp(); },
      starClose: e => { e.stopPropagation(); this.setState({ starRead: -1, skySel: -1, skyFocus: -1, evidenceFocus: null }); },
      starStop: e => e.stopPropagation(),
      starFixing: !!s.starFixing, starNotFixing: !s.starFixing,
      starStartFix: e => { e.stopPropagation(); this.setState({ starFixing: true }); },
      onStarFix: e => {
        if (e.key !== "Enter" || !e.target.value.trim()) return;
        const nextText = e.target.value.trim();
        const previousText = s.starRead === 99 ? rootText : (liveFacts[s.starRead] || {}).t;
        const f = Object.assign({}, s.factFixes); f[s.starRead] = nextText;
        this.setState({ factFixes: f, starFixing: false, starToast: true });
        this.correctPersome("Personal Model 中的这条判断不准确：「" + (previousText || "") + "」。用户更正为：「" + nextText + "」。");
        clearTimeout(this.toastT);
        this.toastT = setTimeout(() => this.setState({ starToast: false }), 3200);
      },
      starToast: !!s.starToast,
      toastStars: this.stars().filter((_, i) => i % 4 === 0).map(st => ({ style: Object.assign({}, st.style, { opacity: .5, animation: "none" }) })),

      actions: [
        { t: "Rewind", scope: "rewind:read", on: false, tap: () => this.setState({ view: "month", dockOpen: false }) },
        { t: "Swipe", scope: "connectors:read", on: s.mcpOpen, tap: () => this.openMcp() },
        { t: "Share", on: false, tap: () => this.setState({ view: "share", dockOpen: false, copied: false }) }
      ].filter((action) => !s.visitor && (!action.scope || modelScopes.has(action.scope))).map(a => ({
        t: a.t, tap: a.tap, style: pill(a.on), hover: "transform:translateY(-1px)"
      })),

      obsOn: !s.visitor && modelScopes.has("now:read") && !s.obsClosed && s.view === "home",
      obsText: hasSnapshot && live.observation ? live.observation : "你的 Personal Model 正在等待新的个人活动片段。",
      obsGo: () => { if (latestDayKey) this.openDay(latestDayKey, false); },
      obsClose: e => { e.stopPropagation(); this.setState({ obsClosed: true }); },
      askOpen: modelScopes.has("model:ask") && !!s.askOpen,
      askOverlay: !s.visitor && !!s.askOpen,
      askClose: () => this.setState({ askOpen: false, ans: null, askDrop: false }),
      askWrapStyle: s.visitor
        ? { width: "min(560px,86vw)", marginTop: "10px", animation: "wFade .3s ease", zIndex: 3, order: 2 }
        : { position: "fixed", left: "50%", top: "50%", transform: "translate(-50%,-50%)", width: "min(620px,calc(100vw - 36px))", animation: "wZoomIn .22s ease", zIndex: 71 },
      toolsOn: false,
      toolRewind: () => this.setState({ view: "month", dockOpen: false }),
      toolConnect: () => this.openMcp(),
      toolShare: () => this.setState({ view: "share", dockOpen: false, copied: false }),
      connectBtn: { display: "inline-grid", placeItems: "center", width: "30px", height: "30px", borderRadius: "8px", cursor: "pointer", fontSize: "14px", color: s.mcpOpen ? "#FFFFFF" : "#6E6E73", background: s.mcpOpen ? "#1D1D1F" : "transparent" },
      askDrop: false,
      askFocus: () => this.setState({ askDrop: false }),
      askBlur: () => setTimeout(() => this.setState({ askDrop: false }), 180),
      dropObs: () => latestDayKey ? this.openDay(latestDayKey, false) : this.openDay(29, false),
      dropCal: () => this.setState({ view: "month", rw: "cal", askDrop: false }),
      dropConnect: () => this.openMcp(),
      dropShare: () => this.setState({ view: "share", dockOpen: false, copied: false, askDrop: false }),
      dropGraph: () => this.setState({ view: "month", rw: "graph", askDrop: false }),
      wallOn: false,
      ownerWallOn: !s.visitor && !!s.ownerWall,
      ownerWallClose: () => this.setState({ ownerWall: false }),
      dropWall: () => this.setState({ ownerWall: true, askDrop: false, dockOpen: false }),
      hardFacts: liveFacts.slice(0, 3).map((fact) => ({ t: fact.t, r: fact.r })),
      wall: s.wall,
      ph: s.visitor ? "ask this model anything — 没做过的事它会直说" : s.ph,
      hasAns: !!s.ans, ansText: s.ans ? s.ans[0] : "", ansMeta: s.ans ? s.ans[1] : "",
      ansGo: !!(s.ans && s.ans[2] && !s.visitor), ansOpen: () => this.openDay(s.ans[2], false),
      ansFixing: !!s.ansFixing,
      ansFixStart: () => this.setState({ ansFixing: true }),
      onAnsFix: e => {
        if (e.key !== "Enter" || !e.target.value.trim()) return;
        const nextText = e.target.value.trim();
        const previousText = s.ans ? s.ans[0] : "";
        this.setState({ ans: [nextText, s.persomeConnected ? "已写回 Persome · correct_memory" : "已在卡片中改写 · Persome 离线", null], ansFixing: false, starToast: true });
        this.correctPersome("Personal Model 之前的回答不准确：「" + previousText + "」。用户更正为：「" + nextText + "」。");
        clearTimeout(this.toastT);
        this.toastT = setTimeout(() => this.setState({ starToast: false }), 3200);
      },
      onAsk: e => {
        if (e.key !== "Enter") return;
        const q = e.target.value.trim();
        if (!q) {
          if (s.visitor) return;
          const livePrompt = Array.isArray(live.proactive) && live.proactive.length ? live.proactive[s.ri % live.proactive.length] : null;
          if (hasSnapshot && livePrompt) {
            this.setState({ ans: [livePrompt.title + "——" + livePrompt.why, "Persome · 最近活动 · ⏎ 下一条", livePrompt.day || null], ri: (s.ri + 1) % live.proactive.length });
            return;
          }
          const r = REM[s.ri % REM.length];
          this.setState({ ans: [r[0], "Personal Model · 等待个人依据", null], ri: (s.ri + 1) % REM.length });
          return;
        }
        e.target.value = "";
        if (s.visitor) this.askPersome(q, true);
        else if (hasSnapshot) this.askPersome(q, false);
        else {
          this.setState({ askDrop: false, ans: ["本机 Personal Model 暂时无法回答。", "Persome · 未返回个人依据", null] });
          this.loadPersome(true);
        }
      },

      dockOpen: s.dockOpen && !s.visitor,
      dockSummary: hasSnapshot ? "最近出现的应用" : "可连接的应用",
      dockSummarySub: hasSnapshot ? "来自 Persome + Coast 的最近活动" : "尚未读取到个人活动",
      dock: dockSource.map((d, i) => {
        const sel = s.revIdx === i && d.on;
        return {
          name: d.name, icon: d.icon, iconUrl: appIconUrl(d.app || d.name), on: d.on, off: !d.on,
          sub: d.on ? (d.cites || d.usageTime || "最近出现过") : "最近没有记录",
          chip: { display: "inline-flex", alignItems: "center", gap: "8px", padding: "7px 14px 7px 8px", borderRadius: "99px", cursor: "pointer", userSelect: "none", transition: "transform .18s, box-shadow .18s",
            background: d.on ? "rgba(255,255,255,.82)" : "rgba(255,255,255,.42)",
            backdropFilter: "blur(20px) saturate(1.5)", WebkitBackdropFilter: "blur(20px) saturate(1.5)",
            color: d.on ? "#1D1D1F" : "#6E6E73",
            boxShadow: sel ? "inset 0 0 0 1.5px #1D1D1F, 0 8px 20px -10px rgba(0,0,0,.25)"
              : d.on ? "inset 0 1px 0 rgba(255,255,255,.9), inset 0 0 0 1px rgba(0,0,0,.06), 0 6px 18px -10px rgba(0,0,0,.2)"
              : "inset 0 0 0 1px rgba(0,0,0,.07)",
            animation: d.snap && Date.now() - d.snap < 900 ? "wSnap .5s cubic-bezier(.34,1.56,.64,1)" : "none" },
          badge: { display: "inline-grid", placeItems: "center", width: "26px", height: "26px", borderRadius: "7px", fontFamily: "'SF Mono',ui-monospace,Menlo,monospace", fontSize: "10.5px", fontWeight: 600, flexShrink: 0,
            background: d.on ? d.tint || "#EFEDE7" : "rgba(0,0,0,.05)",
            color: d.on ? d.fg || "#3B3833" : "#A8A39A" },
          tap: e => { if (d.on) this.startRev(sel ? -1 : i); }
        };
      }),
      revOpen: s.revIdx >= 0 && !!dockSource[s.revIdx] && dockSource[s.revIdx].on,
      revTitle: s.revIdx >= 0 ? (dockSource[s.revIdx].revs.length ? dockSource[s.revIdx].name + " 最近留下的活动" : dockSource[s.revIdx].name + " 最近没有可展示的活动。") : "",
      revLiveOn: false,
      revs: (s.revIdx >= 0 ? dockSource[s.revIdx].revs : []).map((r, i) => ({
        t: r.t, rc: r.rc || "", x: r.x || r.i || "",
        row: { display: "flex", gap: "14px", alignItems: "baseline", padding: "11px 2px", borderTop: "1px solid rgba(0,0,0,.07)", opacity: i < (s.revStep || 0) ? 1 : 0, transform: i < (s.revStep || 0) ? "none" : "translateY(6px)", transition: "opacity .45s ease, transform .45s ease" }
      })),
      revFoot: s.revIdx >= 0 && dockSource[s.revIdx].revs.length ? "这里只展示实际捕获到的活动，不推断调用记录" : "",
      vaultGo: () => this.setState({ view: "year", dockOpen: false, revIdx: -1 }),
      flying: s.flying,
      flyStyle: s.flying ? {
        position: "fixed", zIndex: 90, width: "64px", height: "40px", pointerEvents: "none",
        left: (s.flyGo ? s.flyTo.x : s.flyFrom.x) - 32 + "px",
        top: (s.flyGo ? s.flyTo.y : s.flyFrom.y) - 20 + "px",
        transform: s.flyGo ? "scale(.45) rotate(8deg)" : "scale(1) rotate(-4deg)",
        opacity: s.flyGo ? .9 : 1,
        transition: "left .6s cubic-bezier(.5,.05,.3,1), top .6s cubic-bezier(.5,.05,.3,1), transform .6s cubic-bezier(.5,.05,.3,1)"
      } : {},

      yearMonths: YEAR_MONTHS.map((t, i) => ({
        t,
        style: { fontFamily: "'SF Mono',ui-monospace,Menlo,monospace", fontSize: "9.5px", letterSpacing: ".12em", color: i === 5 ? "#1D1D1F" : "#B8B5AE", cursor: i >= 5 ? "pointer" : "default", fontWeight: i === 5 ? 700 : 400, paddingBottom: "2px" },
        hover: i >= 5 ? "color:#2B47E0" : "",
        tap: i >= 5 ? () => this.setState({ view: "month" }) : null
      })),
      yearCells: this.yearCells(),
      backYear: () => this.setState({ view: "year" }),
      rwFiltersOn: !!s.rwDrop,
      rwFocus: () => this.setState({ rwDrop: true }),
      rwBlur: () => setTimeout(() => this.setState({ rwDrop: false }), 200),
      spotlightSearch: e => {
        if (e.key !== "Enter") return;
        const q = e.target.value.trim();
        if (!q) return;
        e.target.value = "";
        const isConfiding = /(?:我最近|我觉得|我发现|我好像|我有点|我一直|我其实|我想|我不想|我害怕|我担心|我很累|我好累|我很开心|我很难受|我很迷茫|我在纠结|说不上来|不知道为什么)/.test(q);
        const isQuestion = /[？?]$|^(?:我)?(?:上周|昨天|今天|之前|什么时候|为什么|怎么|如何|哪里|哪次|有没有|是否|能不能|是什么)/.test(q);
        if (isConfiding && !isQuestion) {
          this.reflectPersome(q);
          return;
        }
        const pool = hasSnapshot ? liveDays : [];
        const hit = pool.find(d => (d.events || []).some(ev => `${ev.title} ${ev.io} ${ev.detail || ""}`.toLowerCase().includes(q.toLowerCase())) || String(d.narr || "").toLowerCase().includes(q.toLowerCase()) || String(d.portrait || "").toLowerCase().includes(q.toLowerCase()));
        if (hit) this.openDay(hit.key, false);
        else {
          this.setState({ askOpen: true });
          if (isQuestion) this.askPersome(q, false);
          else this.reflectPersome(q);
        }
      },
      rwSearch: e => {
        if (e.key !== "Enter") return;
        const q = e.target.value.trim(); if (!q) return;
        e.target.value = "";
        const pool = hasSnapshot ? liveDays : [];
        const hit = pool.find(d => (d.events || []).some(ev => (ev.title + ev.io + (ev.detail || "")).toLowerCase().indexOf(q.toLowerCase()) >= 0) || (d.narr || "").toLowerCase().indexOf(q.toLowerCase()) >= 0 || (d.portrait || "").toLowerCase().indexOf(q.toLowerCase()) >= 0);
        if (hit) this.openDay(hit.key, false);
      },
      rwTimes: hasSnapshot ? liveDays.slice(0, 3).map((d, i) => ({ t: i === 0 ? "最近一天" : d.short, tap: () => this.openDay(d.key, false) })) : [],
      rwApps: (hasSnapshot ? (live.apps || []).map(a => [a.name, a.icon, a.color, "#FFFFFF", a.time, a.day]) : []).map(([t, ic, bg, fg, h, day]) => ({
        t, ic, h, iconUrl: appIconUrl(t),
        badge: { display: "inline-grid", placeItems: "center", width: "22px", height: "22px", borderRadius: "6px", background: bg, color: fg, fontStyle: "normal", fontSize: "10px", fontWeight: 600 },
        tap: () => this.openDay(day, false)
      })),
      graphOn: false, calOn: true,
      rwCal: () => this.setState({ rw: "cal" }),
      rwGraph: () => this.setState({ view: "sky", starRead: -1, skySel: -1, skyFocus: -1, evidenceFocus: null }),
      rwCalStyle: { fontSize: "11.5px", padding: "4px 14px", borderRadius: "6.5px", cursor: "pointer", userSelect: "none", color: s.rw !== "graph" ? "#1D1D1F" : "#6E6E73", fontWeight: s.rw !== "graph" ? 600 : 400, background: s.rw !== "graph" ? "#FFFFFF" : "transparent", boxShadow: s.rw !== "graph" ? "0 1px 3px rgba(0,0,0,.08)" : "none" },
      rwGraphStyle: { fontSize: "11.5px", padding: "4px 14px", borderRadius: "6.5px", cursor: "pointer", userSelect: "none", color: s.rw === "graph" ? "#1D1D1F" : "#6E6E73", fontWeight: s.rw === "graph" ? 600 : 400, background: s.rw === "graph" ? "#FFFFFF" : "transparent", boxShadow: s.rw === "graph" ? "0 1px 3px rgba(0,0,0,.08)" : "none" },
      gEdges: (() => {
        const N = this.gNodes();
        const pairs = [];
        for (let i = 1; i < N.length; i++) pairs.push([0, i]);
        for (let i = 2; i < N.length; i += 2) pairs.push([i - 1, i]);
        return pairs.map(([a,b]) => ({
          x1: N[a].x * 8, y1: N[a].y * 5.5, x2: N[b].x * 8, y2: N[b].y * 5.5,
          w: (a === 0 || b === 0) ? 2 : 1
        }));
      })(),
      gNodes: this.gNodes().map(n => ({
        label: n.label, sub: n.sub,
        style: { position: "absolute", left: n.x + "%", top: n.y + "%", transform: "translate(-50%,-50%)", width: n.r * 2 + "px", height: n.r * 2 + "px", borderRadius: "50%", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "1px", cursor: "pointer", textAlign: "center", transition: "transform .18s",
          background: n.hot ? "#1D1D1F" : "rgba(255,255,255,.85)",
          boxShadow: n.hot ? "0 14px 32px -10px rgba(0,0,0,.45)" : "inset 0 1px 0 rgba(255,255,255,.9), 0 0 0 1px rgba(0,0,0,.06), 0 6px 16px -8px rgba(0,0,0,.12)" },
        labelStyle: { fontSize: n.r > 50 ? "15px" : n.r > 34 ? "12.5px" : "10.5px", fontWeight: 650, letterSpacing: "-.01em", color: n.hot ? "#FFFFFF" : "#1D1D1F", lineHeight: 1.2 },
        subStyle: { fontFamily: "'SF Mono',ui-monospace,Menlo,monospace", fontSize: "8.5px", color: n.hot ? "rgba(255,255,255,.65)" : "#AEAEB2", letterSpacing: ".04em" },
        tap: () => this.openDay(n.day, false)
      })),
      gNote: hasSnapshot ? ((live.themes || []).length + " 个实时主题 · 来自最近 7 天的 Persome 活动；节点大小只表示当前注意力。") : "等待 Personal Model 返回个人主题。",
      backMonth: () => this.setState({ view: "month", day: null }),
      dows: ["M", "T", "W", "T", "F", "S", "S"].map(t => ({ t })),
      days: this.calendar(),

      dayOp: s.shadow ? .68 : 1,
      isReal: s.day != null && !s.shadow, isShadow: s.shadow,
      coastHasFrame: !!coastFrame && !s.coastFrameFailed,
      coastShowFallback: !coastFrame || !!s.coastFrameFailed,
      coastFrameUrl: coastFrame ? "/api/persome/frame?id=" + encodeURIComponent(coastFrame.id) : "",
      dayHeaderTitle: day && day.futureDay ? "Tomorrow" : "Rewind",
      dayMemoryOn: !(day && day.futureDay),
      dayFutureOn: !!(day && day.futureDay),
      coastFrameApp: coastFrame ? coastFrame.app : (s.shadow ? "Tomorrow Shadow" : "Persome"),
      coastFrameTime: coastFrame ? coastFrame.time : "—",
      coastFrameTitle: coastFrame ? coastFrame.title : (s.shadow ? "这一天还没有发生" : "当天没有可用的画面"),
      coastMomentTitle: coastFrame ? coastFrame.title : (day ? day.title : (SHADOW_TITLES[s.day] || "")),
      coastMomentDetail: nearestEvent
        ? (nearestEvent.detail || nearestEvent.io || "")
        : coastFrame
          ? coastFrame.app + " · Coast 捕获的真实画面"
          : (s.shadow ? "按最近两周的工作节奏生成；明晚回来验证。" : (day ? day.narr : "")),
      coastSource: day && day.coastSource ? day.coastSource : (s.shadow ? "Persome · Tomorrow Shadow" : "Coast · 暂无画面"),
      coastPlayhead,
      coastIndexLabel: coastFrames.length ? (coastIdx + 1) + " / " + coastFrames.length : "0 / 0",
      coastFirstTime: coastFrames.length ? coastFrames[0].time : "—",
      coastLastTime: coastFrames.length ? coastFrames[coastFrames.length - 1].time : "—",
      coastSegments: coastFrames.map((frame, index) => ({
        w: Math.max(2, Number(frame.duration) || 2),
        bg: frame.color || "#6E6E73",
        op: index === coastIdx ? 1 : .78,
        ring: index === coastIdx ? "inset 0 0 0 2px rgba(255,255,255,.95),0 0 0 1px rgba(0,0,0,.18)" : "none",
        tip: frame.time + " · " + frame.app + " · " + frame.title,
        tap: () => this.setState({ coastIdx: index, coastFrameFailed: false, expanded: -1, dayAns: null })
      })),
      coastApps: (day && Array.isArray(day.apps) && day.apps.length
        ? day.apps.slice(0, 7).map((app) => ({ name: app[0], color: app[1], time: app[2] }))
        : Object.values(coastAppTotals)
            .sort((a, b) => b.seconds - a.seconds)
            .slice(0, 7)
            .map((app) => ({ name: app.name, color: app.color, time: app.frames + " frames" }))
      ).map((app) => ({
        n: app.name,
        c: app.color,
        h: app.time,
        iconUrl: appIconUrl(app.name),
        active: coastFrame && coastFrame.app === app.name ? "#1D1D1F" : "#8A8780"
      })),
      coastPrevOff: coastIdx <= 0,
      coastNextOff: coastIdx < 0 || coastIdx >= coastFrames.length - 1,
      coastPrevOpacity: coastIdx <= 0 ? .35 : 1,
      coastNextOpacity: coastIdx < 0 || coastIdx >= coastFrames.length - 1 ? .35 : 1,
      coastPrev: () => {
        if (coastIdx > 0) this.setState({ coastIdx: coastIdx - 1, coastFrameFailed: false, dayAns: null });
      },
      coastNext: () => {
        if (coastIdx >= 0 && coastIdx < coastFrames.length - 1) this.setState({ coastIdx: coastIdx + 1, coastFrameFailed: false, dayAns: null });
      },
      coastScrub: e => this.setState({ coastIdx: Number(e.target.value), coastFrameFailed: false, expanded: -1, dayAns: null }),
      coastRangeMax: Math.max(0, coastFrames.length - 1),
      coastRangeValue: Math.max(0, coastIdx),
      coastFrameLoaded: () => {
        if (s.coastFrameFailed) this.setState({ coastFrameFailed: false });
      },
      coastFrameError: () => this.setState({ coastFrameFailed: true }),
      rewindHighlightsOn: rewindHighlights.length > 0,
      rewindHighlights: rewindHighlights.map(({ event, eventIndex, frameIndex }) => ({
        time: event.t,
        title: event.title,
        detail: event.detail || event.io || "",
        indexLabel: String(eventIndex + 1).padStart(2, "0"),
        style: { display: "grid", gridTemplateColumns: "44px minmax(0,1fr) auto auto", gap: "13px", alignItems: "start", padding: "12px 0", borderTop: "1px solid #E7E4DE", cursor: "pointer", color: frameIndex === coastIdx ? "#1D1D1F" : "#57544E" },
        tap: () => this.setState({ coastIdx: frameIndex, coastFrameFailed: false, expanded: eventIndex, dayAns: null }),
        skyTap: e => {
          e.stopPropagation();
          this.openEvidenceSky({
            id: event.sourceId || event.receipt || `rewind_${s.day}_${eventIndex}`,
            kind: "REWIND · EVIDENCE",
            title: event.title,
            detail: event.detail || event.io || "",
            day: s.day,
            eventIndex,
            receipt: event.sourceId || event.receipt || `event_${eventIndex + 1}`,
          });
        }
      })),
      evidenceSteps: [
        { label: "觉察", note: "最近的我发生了什么", tap: null },
        { label: "Why", note: "Rewind / Evidence", tap: () => this.setState({ view: "sky", starRead: -1, skySel: -1, skyFocus: -1, evidenceFocus: null }) },
        { label: "Correct", note: "准确吗？让模型继续学习", tap: () => this.setState({ fixing: true }) },
        { label: "Act", note: "带着记忆去行动", tap: () => this.openMcp() },
        { label: "Share", note: "哪些部分代表我", tap: () => this.setState({ view: "share", copied: false }) },
      ].map((step, index) => ({
        ...step,
        index: String(index + 1).padStart(2, "0"),
        active: index === 1,
        style: {
          flex: "1 1 120px",
          minWidth: "110px",
          padding: "10px 0",
          cursor: step.tap ? "pointer" : "default",
          color: index === 1 ? "#1D1D1F" : "#77736C",
          borderTop: index === 1 ? "1.5px solid #1D1D1F" : "1px solid #DEDCD6"
        }
      })),
      dayFutureEvents: dayFutureEvents.map((event) => ({
        time: event.time,
        title: event.title,
        detail: event.detail,
        confidence: event.confidence || "也许",
        iconUrl: appIconUrl(event.app || event.title)
      })),
      observationRecorded: day?.observation?.recordedTime || (day && day.totalTime ? day.totalTime : "—"),
      observationLeisure: day?.observation?.leisureTime || "0m",
      observationLeisureNote: day?.observation?.leisureNote || "没有发现能明确归类为娱乐的片段。",
      observationSwitches: String(day?.observation?.switches ?? Math.max(0, (day?.events?.length || 1) - 1)),
      observationFocus: day?.observation?.focusNote || (day?.portrait || ""),
      observationHuman: day?.observation?.humanNote || "这里不评价效率，只帮你看见工作之外发生过什么。",
      dayTakeaway: day?.observation?.takeaway || day?.taught || "看见这一天，比给它打分更重要。",
      dayReadingOn: !!dayReading && !s.shadow,
      dayReadingTitle: dayReading?.title || "今天的你",
      dayReadingStatement: dayReading?.statement || day?.portrait || "",
      dayReadingLines: dailyReadingLines,
      dayReadingTension: dayReading?.tension || "",
      modelUpdatesOn: modelUpdates.length > 0 && !s.shadow,
      modelUpdates,
      dailyUnderlineHint: s.dailyUnderline ? "已划线 · 点右侧生成分享卡" : "点一句划线",
      dayLetterOn: dailyLetterLines.length > 0 && !s.shadow,
      dayLetterSalutation: dailyLetterSalutation,
      dayLetterLines: dailyLetterLines,
      dayRootLine,
      dayRootDescription,
      dayShareCard: () => openDailyShare(
        dayRootText || dayReading?.statement || day?.portrait || "",
        day?.source || day?.title,
        "today's root · remembered by my model",
      ),
      dayTl: day && day.tl ? day.tl.map(b => ({
        w: b.w, bg: b.c || "#EFEEE9", tip: b.tip || "",
        cur: b.ev == null ? "default" : "pointer",
        tap: () => { if (b.ev != null) this.setState({ expanded: b.ev }); }
      })) : [],
      dayApps: day && day.apps ? day.apps.map(a => ({ n: a[0], c: a[1], h: a[2] })) : [],
      dayTitle: s.shadow ? SHADOW_TITLES[s.day] : day ? day.title : "",
      dayTotal: day && day.totalTime ? day.totalTime : "—",
      dayTicks: day && day.events && day.events.length
        ? [day.events[0].t, ...day.events.slice(1, 4).map(e => e.t), day.events[day.events.length - 1].t].filter((t, i, arr) => arr.indexOf(t) === i).map(t => ({ t }))
        : ["09:00", "12:00", "15:00", "18:00", "21:00", "24:00"].map(t => ({ t })),
      daySource: day && day.source ? day.source : "Persome · Personal Model",
      portrait: s.portraits[s.day] || (day ? day.portrait : ""),
      portraitReceipt: day ? "Persome · 由当天 " + day.events.length + " 个个人活动段归纳" : "",
      corrected: !!s.corrected[s.day], fixing: s.fixing,
      startFix: () => this.setState({ fixing: true }),
      onFix: e => {
        if (e.key !== "Enter" || !e.target.value.trim()) return;
        const p = Object.assign({}, s.portraits); p[s.day] = e.target.value.trim();
        const c = Object.assign({}, s.corrected); c[s.day] = true;
        this.setState({ portraits: p, corrected: c, fixing: false, starToast: true });
        clearTimeout(this.toastT);
        this.toastT = setTimeout(() => this.setState({ starToast: false }), 3200);
      },
      dayGlyph: activeGlyph.map((p, i) => {
        const li = day ? day.lit.indexOf(i) : -1;
        const isLit = s.lit && li >= 0;
        return { bg: p ? "#F5F5F4" : "#2C2C2E", anim: isLit ? "wLit 1.1s ease " + (li * .6) + "s both" : "none" };
      }),
      narrative: s.shadow ? "这一天还没发生。按过去两周的样子，它大概率长这样——错了，明晚就会被划掉。" : day ? day.narr : "",
      evBorder: s.shadow ? "1px dashed #E7E4DE" : "1px solid #E7E4DE",
      dayShort: s.shadow ? (SHADOW_TITLES[s.day] || "") : day ? day.title : "",
      isShadowNarr: s.shadow,
      events: (s.shadow ? SHADOW_EVENTS : day ? day.events : []).map((e, i) => ({
        t: e.t, title: e.title, io: e.io, detail: e.detail || "",
        frames: (e.frames || []).map(t => ({ t })),
        open: !s.shadow && s.expanded === i,
        cur: s.shadow ? "default" : "pointer",
        hover: s.shadow ? "" : "background:#F7F6F3",
        tri: { color: "#C0BDB6", fontSize: "11px", flexShrink: 0, display: s.shadow ? "none" : "inline-block", transform: !s.shadow && s.expanded === i ? "rotate(90deg)" : "none", transition: "transform .18s" },
        tap: s.shadow ? null : () => this.setState({ expanded: s.expanded === i ? -1 : i })
      })),
      hasDayAns: !!s.dayAns, dayAnsText: s.dayAns ? s.dayAns.text : "", dayAnsAt: s.dayAns ? s.dayAns.at : "",
      onDayAsk: e => {
        if (e.key !== "Enter" || !day) return;
        const q = e.target.value.trim(); if (!q) return;
        e.target.value = "";
        const query = q.toLowerCase();
        const directFrame = coastFrames.findIndex((frame) =>
          String(frame.time || "").indexOf(q) >= 0 ||
          String(frame.app || "").toLowerCase().indexOf(query) >= 0 ||
          String(frame.title || "").toLowerCase().indexOf(query) >= 0
        );
        if (directFrame >= 0) {
          const frame = coastFrames[directFrame];
          this.setState({
            coastIdx: directFrame,
            coastFrameFailed: false,
            expanded: -1,
            dayAns: { text: frame.time + " · " + frame.app + " · " + frame.title, at: frame.time }
          });
          return;
        }
        let idx = day.events.findIndex(ev => q.indexOf(ev.t) >= 0 || ev.t.indexOf(q) >= 0);
        if (idx < 0) idx = day.events.findIndex(ev => (ev.title + ev.io + (ev.detail || "")).indexOf(q) >= 0);
        if (idx < 0) idx = /下午|afternoon/i.test(q) ? 1 : /晚|night|evening/i.test(q) ? 2 : /早|上午|morning/i.test(q) ? 0 : -1;
        if (idx < 0) { this.setState({ dayAns: { text: "这一天没有和「" + q + "」对上的段。", at: "—" } }); return; }
        const ev = day.events[idx];
        const eventMinute = /^\d{2}:\d{2}$/.test(ev.t || "") ? Number(ev.t.slice(0, 2)) * 60 + Number(ev.t.slice(3, 5)) : 0;
        const frameIdx = coastFrames.length
          ? coastFrames.reduce((best, frame, frameIndex) => {
              const frameMinute = /^\d{2}:\d{2}$/.test(frame.time || "") ? Number(frame.time.slice(0, 2)) * 60 + Number(frame.time.slice(3, 5)) : 0;
              const diff = Math.abs(frameMinute - eventMinute);
              return diff < best.diff ? { index: frameIndex, diff } : best;
            }, { index: coastIdx, diff: Infinity }).index
          : -1;
        this.setState({ expanded: idx, coastIdx: frameIdx, coastFrameFailed: false, dayAns: { text: ev.t + " 你在做「" + ev.title + "」——" + (ev.detail || ev.io), at: ev.t } });
      },
      verdicts: SHADOW_EVENTS.map((e, i) => {
        const v = (s.verdicts || {})[i];
        const btn = on => ({ display: "inline-grid", placeItems: "center", width: "24px", height: "24px", borderRadius: "50%", cursor: "pointer", fontSize: "12px", flexShrink: 0,
          border: "1px solid " + (on ? "transparent" : "#E7E4DE"),
          background: on === "hit" ? "#2B47E0" : on === "miss" ? "#1D1D1F" : "transparent",
          color: on ? "#FFFFFF" : "#AEAEB2" });
        return {
          t: e.t, title: e.title,
          deco: v === "miss" ? "line-through" : "none",
          hitStyle: btn(v === "hit" ? "hit" : null), missStyle: btn(v === "miss" ? "miss" : null),
          hit: () => { const n = Object.assign({}, s.verdicts); n[i] = "hit"; this.setState({ verdicts: n }); },
          miss: () => { const n = Object.assign({}, s.verdicts); n[i] = "miss"; this.setState({ verdicts: n }); }
        };
      }),
      verdictColor: Object.values(s.verdicts || {}).filter(x => x === "hit").length >= 2 ? "#2B47E0" : "#AEAEB2",
      verdictNote: (() => {
        const vs = Object.values(s.verdicts || {});
        const h = vs.filter(x => x === "hit").length;
        if (!vs.length) return "点 ✓ 命中 / ✗ 落空";
        if (h >= 2) return "命中 " + h + "/3";
        return "命中 " + h + "/3 · 落空的影子今晚会被划掉重推";
      })(),
      letter: day ? (day.letter || "") : "",
      dayNarrLabel: hasSnapshot ? "Persome 个人快照 · " : "",
      taught: day ? day.taught : "",
      evCount: day ? day.events.length : 0,
      dayFoot: s.shadow ? "shadow plan · generated from your last 14 days" : (day && day.source ? day.source : "Persome · Personal Model")
    };
  }
}
