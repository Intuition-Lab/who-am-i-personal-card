import { useEffect, useState } from "react";

import { MapView } from "@/components/MapView";
import { PersonalCard } from "@/components/PersonalCard";
import { QuickBox } from "@/components/QuickBox";
import { SettingsView } from "@/components/SettingsView";
import { SetupView } from "@/components/SetupView";
import { Sky } from "@/components/Sky";
import { SwipeView } from "@/components/SwipeView";
import { usePersonalModel } from "@/hooks/use-personal-model";

type Surface = "main" | "quick";

function routeFromLocation() {
  return new URLSearchParams(window.location.search).get("route") || "home";
}

function TitleBar({ route, onNavigate }: { route: string; onNavigate: (route: string) => void }) {
  const [open, setOpen] = useState(false);
  return (
    <header className="titlebar">
      <span aria-hidden="true" />
      <span className="window-title">Persome</span>
      <div className="titlebar-right"><span className="live-dot" /><span>Personal Model · local</span><button aria-expanded={open} aria-label="Open Persome navigation" className="menu-trigger" onClick={() => setOpen((current) => !current)} type="button">☰</button></div>
      {open && (
        <nav aria-label="Persome" className="app-menu">
          {[{ id: "home", label: "Personal Card" }, { id: "map:nebula", label: "Map" }, { id: "map:rewind:day", label: "Rewind" }, { id: "swipe", label: "Swipe Your Card" }, { id: "settings", label: "Trust & Settings" }].map((item) => (
            <button className={route.startsWith(item.id.split(":")[0]) ? "active" : ""} key={item.id} onClick={() => { onNavigate(item.id); setOpen(false); }} type="button">{item.label}<span>↗</span></button>
          ))}
        </nav>
      )}
    </header>
  );
}

export function App() {
  const surface = (new URLSearchParams(window.location.search).get("surface") === "quick" ? "quick" : "main") as Surface;
  const [route, setRoute] = useState(routeFromLocation);
  const [toast, setToast] = useState("");
  const [toastVisible, setToastVisible] = useState(false);
  const model = usePersonalModel();

  useEffect(() => window.persomeDesktop?.onNavigate((nextRoute) => setRoute(nextRoute)), []);

  function navigate(nextRoute: string) {
    setRoute(nextRoute);
  }

  function showToast(message: string) {
    setToast(message);
    setToastVisible(true);
    window.setTimeout(() => setToastVisible(false), 2600);
  }

  if (surface === "quick") {
    return (
      <main className="surface-quick">
        <QuickBox onModelChanged={model.refresh} onNavigate={navigate} onToast={showToast} snapshot={model.snapshot} surface="quick" />
        <div aria-live="polite" className={`toast${toastVisible ? " show" : ""}`}>{toast}</div>
      </main>
    );
  }

  const section = route.split(":")[0];
  const isHome = section === "home";
  return (
    <main className="desktop">
      <div className="app-window">
        <TitleBar onNavigate={navigate} route={route} />
        {model.phase === "setup" && <SetupView message={model.message} onReady={model.refresh} onToast={showToast} />}
        {model.phase === "error" && (
          <section className="screen setup-screen active"><article className="setup-card"><span className="living-kicker">PERSOME · LOCAL SERVICE</span><h1>Persome could not open your model</h1><p>{model.message}</p><button className="primary setup-action" onClick={() => void model.refresh()} type="button">Try again</button></article></section>
        )}
        {model.phase !== "setup" && model.phase !== "error" && isHome && (
          <section aria-label="Personal Card and Quick Box" className="screen home-screen active">
            <Sky className="home-aurora" colors="2a303a,736d79,bf927f" glow={0.12} glowPosition={[0.5, 0.34]} speed={0.18} />
            <div className="home-vignette" />
            <div className="home-content">
              <PersonalCard onOpenMap={() => navigate("map:nebula")} onOpenSwipe={() => navigate("swipe")} onToast={showToast} snapshot={model.snapshot} />
              <div className="quick-host"><QuickBox defaultMode={route === "home:ask" ? "ask" : "jot"} onModelChanged={model.refresh} onNavigate={navigate} onToast={showToast} snapshot={model.snapshot} surface="main" /></div>
            </div>
          </section>
        )}
        {model.phase !== "setup" && section === "map" && <MapView onBack={() => navigate("home")} onNavigate={navigate} onToast={showToast} route={route} snapshot={model.snapshot} />}
        {model.phase !== "setup" && section === "swipe" && <SwipeView onBack={() => navigate("home")} onModelChanged={model.refresh} onToast={showToast} snapshot={model.snapshot} />}
        {model.phase !== "setup" && section === "settings" && <SettingsView onBack={() => navigate("home")} onNavigate={navigate} onToast={showToast} snapshot={model.snapshot} />}
        {model.phase === "loading" && !model.snapshot && <div className="model-loading"><span />Loading your Personal Model…</div>}
        <div aria-live="polite" className={`toast${toastVisible ? " show" : ""}`}>{toast}</div>
      </div>
    </main>
  );
}
