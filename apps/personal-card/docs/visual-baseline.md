# V5 visual baseline

This document freezes the existing Personal Card V5 experience before the
Personal Model data layer is changed. E0 must not change
`WhoAmI v5.template.html`, `WhoAmI v5.logic.js`, or their styles.

## Source served on port 8772

Checked on 2026-08-07:

- Listener: `node persome-card-server.mjs`
- Listener PID at capture setup: `27257`
- Process working directory:
  the approved `personal-card-v5-persome-live` handoff package
- `GET http://127.0.0.1:8772/`: `200 OK`
- `persome-card-server.mjs` SHA-256:
  `c3a34b8f24bb3eaa91a27038544fea6e39b9f7e39c000638b8e6a358e693e6c4`
- `WhoAmI v5.template.html` SHA-256:
  `9bde423cd9975f68379117b893c71c9f5cf4b4be23ace64d62bc6c40b2568b2b`
- `WhoAmI v5.logic.js` SHA-256:
  `05bbe9ed4cd65225096482ed84bc026d117e2a601ce821606423c448c26d73d3`

Recheck the listener before capturing:

```bash
lsof -nP -iTCP:8772 -sTCP:LISTEN
lsof -a -p "$(lsof -tiTCP:8772 -sTCP:LISTEN | head -n1)" -d cwd
curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8772/
```

## Viewports

The E0 viewport is **1440 × 1000 CSS pixels**, device scale factor 1. Use this
single viewport for all seven E0 reference images. Responsive coverage belongs
to E6 and must not replace the E0 references.

## Required reference images

Committed images live under `tests/visual/baselines/`:

| File | Required state |
| --- | --- |
| `home-1440x1000.png` | Initial Personal Card home after the page settles |
| `swipe-1440x1000.png` | Swipe page, before starting the reader animation |
| `report-collapsed-1440x1000.png` | Connector result list with report rows closed |
| `report-expanded-1440x1000.png` | The first available report opened |
| `rewind-1440x1000.png` | Rewind calendar/document view |
| `sky-1440x1000.png` | Memory Sky overview, no evidence card selected |
| `identity-1440x1000.png` | Identity page |

Do not replace a reference merely because a comparison changed. First prove
that the difference is intentional and that the V5 UI, typography, motion,
copy hierarchy, and interaction path were not redesigned.

## Stable interaction paths

The current prototype does not expose test IDs. Use the existing accessible
labels and visible copy; do not add selectors to the production template for
E0.

1. **Home** — navigate to `/`, wait for `document.fonts.ready`, then wait one
   animation settling interval (1.2 seconds).
2. **Swipe** — from Home, click the exact visible text `Swipe your card`.
   Confirm the element
   `[aria-label="Swipe your Personal Card to connected agents"]` is visible.
   Capture before clicking the reader.
3. **Report collapsed** — on Swipe, wait for `.wReportHead`; capture without
   clicking a row.
4. **Report expanded** — click the first visible `.wReportHead`, wait for the
   report body below it to become visible, then capture.
5. **Rewind** — from Home, click
   `[title="Rewind — 回到某一天"]`. Confirm
   `[aria-label="Rewind timeline"]` is present.
6. **Sky** — from Home, click `[title^="巡星"]`. Confirm
   `[data-screen-label="Memory Sky"]` is visible and no evidence detail is
   selected.
7. **Identity** — from Home, click the exact visible text
   `My Page · Identity ↗`. Confirm the breadcrumb contains `Identity`.

Reload `/` before each scenario so one view's state cannot leak into the next
reference. Do not start the Swipe animation when creating the static Swipe
baseline; the moving card belongs in the E6 interaction test.

## Capture procedure

1. Start the existing server from this source directory.
2. Set the browser viewport to 1440 × 1000 and device scale factor 1.
3. Capture each scenario above as a viewport screenshot (not a full-page
   screenshot).
4. Record browser console `warning` and `error` entries.
5. Confirm every PNG is 1440 × 1000 and review it visually before accepting it.

The E0 baseline captures the live V5 state. Dynamic clock and local Persome
content can make pixel comparison noisy. Once the Cecilia fixture route exists,
E6 should use `/?model=cecilia` for deterministic comparisons while retaining
these E0 files as the pre-migration visual reference.

## Repeatable command

E6 adds a Playwright Core harness that launches the installed macOS Google
Chrome at the fixed viewport, starts an isolated fixture server, exercises the
existing V5 interactions, and writes the current screenshots without replacing
the frozen E0 references:

```bash
npm run visual:baseline
```

Generated images live in `tests/visual/current/`. The same harness also proves
the Cecilia → Lin → Cecilia runtime switch, failed-switch rollback, Swipe,
other-Agent picker, Report expansion, Rewind, Evidence, Identity, and Public
Visitor denial:

```bash
npm run test:browser
```
