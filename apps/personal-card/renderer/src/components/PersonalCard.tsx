import { type CSSProperties, type PointerEvent, useMemo, useRef, useState } from "react";

import { Sky } from "@/components/Sky";
import type { PersonalModelSnapshot } from "@/lib/api";

const palettes = {
  silver: { name: "Silver Rain", colors: "767e8b,c6cdd7,ebe4d2" },
  giverny: { name: "Giverny", colors: "2e4a28,8fa845,c4cce2" },
  dawn: { name: "Dawn", colors: "e9dfd2,d9a088,96a8d8" },
} as const;

type PaletteName = keyof typeof palettes;

function seededStars() {
  let seed = 7319;
  const random = () => {
    seed = seed * 16807 % 2147483647;
    return (seed - 1) / 2147483646;
  };
  return Array.from({ length: 44 }, (_, index) => {
    const cluster = index % 3;
    const centerX = [0.34, 0.63, 0.5][cluster];
    const centerY = [0.42, 0.31, 0.67][cluster];
    return {
      left: Math.max(0.07, Math.min(0.93, centerX + (random() - 0.5) * 0.56)) * 100,
      top: Math.max(0.12, Math.min(0.82, centerY + (random() - 0.5) * 0.44)) * 100,
      opacity: 0.34 + random() * 0.56,
      root: index === 18,
    };
  });
}

type PersonalCardProps = {
  snapshot: PersonalModelSnapshot | null;
  onOpenMap: () => void;
  onOpenSwipe: () => void;
  onToast: (message: string) => void;
};

export function PersonalCard({ snapshot, onOpenMap, onOpenSwipe, onToast }: PersonalCardProps) {
  const [flipped, setFlipped] = useState(false);
  const [paletteName, setPaletteName] = useState<PaletteName>("silver");
  const tiltRef = useRef<HTMLDivElement>(null);
  const stars = useMemo(seededStars, []);
  const palette = palettes[paletteName];
  const handle = snapshot?.model.handle || "@you";
  const memberNumber = snapshot?.model.memberNumber || "—";
  const memoryCount = snapshot?.personalModel.memoryCount ?? 0;
  const monthYear = snapshot?.card.monthYear || "FORMING";
  const publicUrl = snapshot?.card.publicUrl || "local · forming";

  function pointerMove(event: PointerEvent<HTMLDivElement>) {
    if (!window.matchMedia("(hover:hover) and (pointer:fine)").matches) return;
    const bounds = event.currentTarget.getBoundingClientRect();
    const x = (event.clientX - bounds.left) / bounds.width - 0.5;
    const y = (event.clientY - bounds.top) / bounds.height - 0.5;
    if (tiltRef.current) {
      tiltRef.current.style.transform = `rotateX(${-y * 5}deg) rotateY(${x * 7}deg)`;
    }
  }

  function clearTilt() {
    if (tiltRef.current) tiltRef.current.style.transform = "";
  }

  return (
    <>
      <div className="home-label">
        <span>Personal Card · as of now</span>
        <div aria-label="Card sky" className="sky-menu">
          <span>{palette.name}</span>
          {(Object.keys(palettes) as PaletteName[]).map((name) => (
            <button
              aria-label={palettes[name].name}
              className={`sky-dot${name === paletteName ? " active" : ""}`}
              key={name}
              onClick={() => {
                setPaletteName(name);
                onToast(`${palettes[name].name} · Card sky updated`);
              }}
              type="button"
            />
          ))}
        </div>
      </div>
      <div
        aria-label="Flip Personal Card"
        aria-pressed={flipped}
        className={`card-stage${flipped ? " flipped" : ""}`}
        onClick={(event) => {
          if (!(event.target as HTMLElement).closest("button")) setFlipped((current) => !current);
        }}
        onKeyDown={(event) => {
          if (event.key === "Enter" || event.key === " ") {
            event.preventDefault();
            setFlipped((current) => !current);
          }
        }}
        onPointerLeave={clearTilt}
        onPointerMove={pointerMove}
        role="button"
        tabIndex={0}
      >
        <div className="card-tilt" ref={tiltRef}>
          <div className="card-flip">
            <article className="card-face card-front">
              <Sky className="sky-canvas" colors={palette.colors} glow={0.18} glowPosition={[0.72, 0.16]} speed={0.52} />
              <div className="card-top micro"><span>№ {memberNumber}</span><span>{monthYear}</span></div>
              <div className="card-bottom">
                <span><span className="card-handle">{handle}</span><span className="card-model">PERSONAL MODEL · {memoryCount.toLocaleString()} MEMORIES</span></span>
                <span className="card-right">ONE OF ONE<br />{publicUrl}</span>
              </div>
            </article>
            <article className="card-face card-back">
              <Sky className="sky-canvas" colors={palette.colors} glow={0.18} glowPosition={[0.72, 0.16]} speed={0.52} />
              <div className="card-back-top micro"><span>✦ Expand Map</span><span>As of now</span></div>
              <div className="card-stars">
                {stars.map((star, index) => (
                  <i
                    className={`card-star${star.root ? " root" : ""}`}
                    key={index}
                    style={{ left: `${star.left}%`, opacity: star.opacity, top: `${star.top}%` } as CSSProperties}
                  />
                ))}
              </div>
              <div className="card-back-bottom">
                <span className="card-handle" style={{ fontStyle: "normal" }}>№ {memberNumber}</span>
                <span>
                  <button className="card-action" onClick={(event) => { event.stopPropagation(); clearTilt(); onOpenMap(); }} type="button">Expand Map</button>
                  <button className="card-action" onClick={(event) => { event.stopPropagation(); clearTilt(); onOpenSwipe(); }} type="button">Swipe to AI</button>
                </span>
                <span className="card-right">{memoryCount.toLocaleString()} MEMORIES</span>
              </div>
            </article>
          </div>
        </div>
      </div>
      <div className="card-caption">Click to flip · the sky is the back</div>
    </>
  );
}
