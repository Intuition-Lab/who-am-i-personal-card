import {
  type CSSProperties,
  type KeyboardEvent,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";

import {
  askModel,
  correctModel,
  jotModel,
  type PersonalModelSnapshot,
} from "@/lib/api";

type QuickMode = "jot" | "ask";
type QuickResult =
  | { kind: "recall"; text: string; evidence: string[] }
  | { kind: "correction"; text: string }
  | null;

type LocalSpeechResultEvent = Event & {
  resultIndex: number;
  results: ArrayLike<ArrayLike<{ transcript: string }> & { isFinal: boolean }>;
};

type LocalSpeechRecognition = EventTarget & {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  processLocally?: boolean;
  start: () => void;
  stop: () => void;
  onresult: ((event: LocalSpeechResultEvent) => void) | null;
  onerror: ((event: Event & { error?: string }) => void) | null;
  onend: (() => void) | null;
};

type LocalSpeechConstructor = new () => LocalSpeechRecognition;

const previewHeat = [
  0.16, 0.55, 0.78, 0.23, 0.62, 0.35, 0.11, 0.2, 0.41, 0.74,
  0.52, 0.81, 0.31, 0.18, 0.64, 0.71, 0.27, 0.48, 0.83, 0.58,
  0.12, 0.67, 0.9, 0.39, 0.24, 0.69, 0.76, 0.34, 0.6, 0.2,
];

function isQuestion(text: string) {
  return /[?？]\s*$/.test(text)
    || /^(what|why|when|where|who|how|can|could|would|did|do|does|is|are|was|were|tell me|remember)\b/i.test(text)
    || /(吗|么|什么|怎么|为什么|何时|哪里|谁|能否|是不是|有没有)[？?]?\s*$/.test(text);
}

function isCorrection(text: string) {
  return /(stop|stopped|ended|结束|停了|不做了|不对|更正|改成)/i.test(text);
}

type QuickBoxProps = {
  surface: "main" | "quick";
  snapshot: PersonalModelSnapshot | null;
  onNavigate: (route: string) => void;
  onToast: (message: string) => void;
  onModelChanged?: () => void;
  defaultMode?: QuickMode;
};

export function QuickBox({
  surface,
  snapshot,
  onNavigate,
  onToast,
  onModelChanged,
  defaultMode = "jot",
}: QuickBoxProps) {
  const [mode, setMode] = useState<QuickMode>(defaultMode);
  const [text, setText] = useState("");
  const [manualJot, setManualJot] = useState(false);
  const [detected, setDetected] = useState(false);
  const [voiceActive, setVoiceActive] = useState(false);
  const [busy, setBusy] = useState(false);
  const [receipt, setReceipt] = useState(false);
  const [result, setResult] = useState<QuickResult>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const recognitionRef = useRef<LocalSpeechRecognition | null>(null);

  const heat = useMemo(() => {
    const days = snapshot?.time.days ?? [];
    if (!days.length) return previewHeat.map(() => 0);
    const values = days.slice(0, 30).map((day) => day.events.length);
    const max = Math.max(1, ...values);
    return Array.from({ length: 30 }, (_, index) => {
      const value = values[values.length - 1 - index];
      return value == null ? 0 : 0.12 + (value / max) * 0.78;
    });
  }, [snapshot]);

  useEffect(() => {
    setMode(defaultMode);
    requestAnimationFrame(() => inputRef.current?.focus());
  }, [defaultMode]);

  useEffect(() => {
    return window.persomeDesktop?.onFocusInput(() => {
      inputRef.current?.focus();
    });
  }, []);

  useEffect(() => () => {
    recognitionRef.current?.stop();
    recognitionRef.current = null;
  }, []);

  useEffect(() => {
    const listener = (event: globalThis.KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key === "/") {
        event.preventDefault();
        setMode((current) => current === "jot" ? "ask" : "jot");
        setDetected(false);
        inputRef.current?.focus();
      }
      if (event.key === "Escape" && surface === "quick") {
        window.persomeDesktop?.closeQuick();
      }
    };
    document.addEventListener("keydown", listener);
    return () => document.removeEventListener("keydown", listener);
  }, [surface]);

  function selectMode(nextMode: QuickMode, keepText = true) {
    setMode(nextMode);
    setDetected(false);
    setResult(null);
    if (!keepText) setText("");
    if (nextMode === "jot") setManualJot(true);
    requestAnimationFrame(() => inputRef.current?.focus());
  }

  function updateText(value: string) {
    setText(value);
    setResult(null);
    if (!value.trim()) {
      setManualJot(false);
      setDetected(false);
      return;
    }
    if (mode === "jot" && !manualJot && isQuestion(value.trim())) {
      setMode("ask");
      setDetected(true);
    }
  }

  async function submit() {
    const value = text.trim();
    if (!value || busy) return;
    setBusy(true);
    setResult(null);
    try {
      if (mode === "jot") {
        await jotModel(value);
        setText("");
        setReceipt(true);
        onToast("Saved locally · Persome");
        window.setTimeout(() => setReceipt(false), 2600);
        await onModelChanged?.();
        return;
      }
      if (isCorrection(value)) {
        await correctModel(value);
        setResult({ kind: "correction", text: "Updated. Your Personal Model has been corrected." });
        await onModelChanged?.();
        return;
      }
      const response = await askModel(value);
      setResult({
        kind: "recall",
        text: response.answer,
        evidence: response.results.slice(0, 3).map((entry) =>
          entry.title || entry.text || entry.reference || "Evidence"
        ),
      });
    } catch (error) {
      onToast(error instanceof Error ? error.message : "Persome could not complete that.");
    } finally {
      setBusy(false);
    }
  }

  function onInputKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      void submit();
    }
  }

  function openRoute(route: string) {
    if (surface === "quick") {
      window.persomeDesktop?.openMain(route);
      return;
    }
    onNavigate(route);
  }

  function toggleVoice() {
    if (voiceActive) {
      recognitionRef.current?.stop();
      recognitionRef.current = null;
      setVoiceActive(false);
      onToast("Voice stopped · review before saving");
      return;
    }
    const speechWindow = window as Window & {
      SpeechRecognition?: LocalSpeechConstructor;
      webkitSpeechRecognition?: LocalSpeechConstructor;
    };
    const Recognition = speechWindow.SpeechRecognition || speechWindow.webkitSpeechRecognition;
    if (!Recognition) {
      onToast("On-device dictation is unavailable on this Mac");
      return;
    }
    const recognition = new Recognition();
    if (!("processLocally" in recognition)) {
      onToast("On-device dictation is unavailable · nothing was recorded");
      return;
    }
    recognition.continuous = false;
    recognition.interimResults = true;
    recognition.lang = navigator.language || "en-US";
    recognition.processLocally = true;
    recognition.onresult = (event) => {
      const transcript = Array.from(event.results)
        .slice(event.resultIndex)
        .map((item) => item[0]?.transcript || "")
        .join("")
        .trim();
      if (transcript) updateText(`${text}${text && !text.endsWith(" ") ? " " : ""}${transcript}`);
    };
    recognition.onerror = (event) => {
      recognitionRef.current = null;
      setVoiceActive(false);
      onToast(event.error === "not-allowed"
        ? "Allow Microphone in System Settings to use local dictation"
        : "Local dictation stopped · nothing was saved");
    };
    recognition.onend = () => {
      recognitionRef.current = null;
      setVoiceActive(false);
      inputRef.current?.focus();
    };
    recognitionRef.current = recognition;
    setVoiceActive(true);
    onToast("Listening on this Mac · nothing has been saved");
    try {
      recognition.start();
    } catch {
      recognitionRef.current = null;
      setVoiceActive(false);
      onToast("Local dictation could not start");
    }
  }

  const typing = text.trim().length > 0;
  const placeholder = voiceActive
    ? "Listening locally…"
    : mode === "ask"
      ? "Ask what you remember…"
      : "Jot something down…";

  return (
    <section
      aria-label="Persome Quick Box"
      className={`quick-box${surface === "quick" ? " compact keyboard-open" : ""}${typing ? " typing" : ""}${detected ? " detected" : ""}`}
      data-mode={mode}
    >
      <div className="quick-inner">
        <div className="input-row">
          <textarea
            aria-label="Jot or ask Persome"
            className="quick-input"
            disabled={busy}
            onChange={(event) => updateText(event.target.value)}
            onKeyDown={onInputKeyDown}
            placeholder={placeholder}
            ref={inputRef}
            rows={1}
            style={{ height: Math.min(96, Math.max(30, 30 + Math.floor(text.length / 64) * 24)) }}
            value={text}
          />
          <span className="shortcut">{mode === "ask" ? "⌘/" : "⌘⇧Space"}</span>
          <button
            aria-label={voiceActive ? "Stop local voice transcription" : "Start local voice transcription"}
            aria-pressed={voiceActive}
            className={`mic${voiceActive ? " recording" : ""}`}
            onClick={toggleVoice}
            type="button"
          >
            <svg aria-hidden="true" viewBox="0 0 16 16">
              <rect fill="none" height="8" rx="2.75" stroke="currentColor" strokeWidth="1.35" width="5.5" x="5.25" y="1.5" />
              <path d="M3.75 7.4v.7a4.25 4.25 0 0 0 8.5 0v-.7M8 12.35v2.15M5.7 14.5h4.6" fill="none" stroke="currentColor" strokeLinecap="round" strokeWidth="1.35" />
            </svg>
          </button>
        </div>

        <div className="mode-row">
          <div style={{ alignItems: "center", display: "flex", gap: 10 }}>
            <div className="mode-switch">
              <button className={`mode-button${mode === "jot" ? " active" : ""}`} onClick={() => selectMode("jot")} type="button">Jot</button>
              <button className={`mode-button${mode === "ask" ? " active" : ""}`} onClick={() => selectMode("ask")} type="button">Ask</button>
            </div>
            <span className="detected-note">
              Question detected · switched to Ask
              <button className="keep-jot" onClick={() => selectMode("jot")} type="button">Keep as jot</button>
            </span>
          </div>
          <span className="shortcut">⌘/</span>
        </div>

        <div className="quick-empty">
          <div className="heat-head"><span>LAST 30 DAYS</span><span>less ░▒▓█ more</span></div>
          <div className="heatmap">
            {heat.map((activity, index) => (
              <button
                aria-label={activity === 0 ? `No captured activity on day ${index + 1}` : `Open day ${index + 1}`}
                className={`heat${activity === 0 ? " gap" : ""}`}
                disabled={activity === 0}
                key={index}
                onClick={() => openRoute("map:rewind:day")}
                style={{ "--a": activity } as CSSProperties}
                type="button"
              />
            ))}
          </div>
          <footer className="quick-foot">
            <div className="time-links">
              <button className="q-link" onClick={() => openRoute("map:rewind:day")}>Today</button><span>·</span>
              <button className="q-link" onClick={() => openRoute("map:rewind:week")}>This week</button><span>·</span>
              <button className="q-link" onClick={() => openRoute("map:rewind:month")}>This month</button><span>·</span>
              <button className="q-link" onClick={() => openRoute("map:nebula")}>Map</button>
            </div>
            <div className="exit-links">
              <button className="q-link soft" onClick={() => openRoute("settings")}>Settings</button>
              <button
                aria-label={surface === "main" ? "Persome app is already open" : "Open the full Persome app"}
                className={`q-link ${surface === "main" ? "current" : "strong"}`}
                onClick={() => surface === "quick"
                  ? window.persomeDesktop?.openMain("home")
                  : onToast("Persome app is already open")}
              >
                {surface === "main" ? "App open" : "Open app"}
              </button>
            </div>
          </footer>
        </div>

        <div className="submit-row">
          <button className="submit" disabled={busy} onClick={() => void submit()} type="button">
            {busy ? "Working…" : mode === "jot" ? "↵  Save" : "↵  Ask"}
          </button>
        </div>
        <div className={`receipt${receipt ? " show" : ""}`}>SAVED · NOW · PERSOME</div>

        <div className="ask-body">
          {result?.kind === "recall" && (
            <div className="answer show">
              <div className="answer-copy">{result.text}</div>
              {result.evidence.length > 0 && (
                <div className="evidence">
                  <span>&gt; EVIDENCE</span>
                  {result.evidence.map((item, index) => (
                    <button key={`${item}-${index}`} onClick={() => openRoute("map:rewind:day")}>{item}</button>
                  ))}
                </div>
              )}
            </div>
          )}
          {result?.kind === "correction" && (
            <div className="answer show">
              <div className="answer-copy">{result.text}</div>
              <div className="diff">
                <div><b>BEFORE</b>previous model understanding</div>
                <div><b>AFTER</b>corrected by you · just now</div>
              </div>
              <div className="evidence">
                <span>YOUR CORRECTION · JUST NOW</span>
                <button onClick={() => openRoute("map:living")}>View in Living Model</button>
              </div>
            </div>
          )}
          <button className="back-jot" onClick={() => selectMode("jot", false)} type="button">Back to jotting</button>
        </div>
      </div>
    </section>
  );
}
