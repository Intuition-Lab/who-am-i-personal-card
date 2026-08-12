import path from "node:path";
import { fileURLToPath } from "node:url";
import { readFile, writeFile } from "node:fs/promises";

import {
  app,
  BrowserWindow,
  dialog,
  globalShortcut,
  ipcMain,
  Menu,
  nativeImage,
  systemPreferences,
  screen,
  session,
  shell,
  Tray,
  utilityProcess,
} from "electron";

const moduleRoot = path.dirname(fileURLToPath(import.meta.url));
const productRoot = path.resolve(moduleRoot, "..");
const serverRoot = app.isPackaged
  ? path.join(process.resourcesPath, "app.asar.unpacked")
  : productRoot;
// The legacy browser preview owns 8772. The desktop shell deliberately uses a
// separate loopback-only port so an older preview cannot be mistaken for the
// Electron backend during an in-place upgrade.
const serverPort = String(process.env.WHOAMI_CARD_PORT || "8773");
const localOrigin = `http://127.0.0.1:${serverPort}`;
const developmentRenderer = process.env.WHOAMI_ELECTRON_RENDERER_URL || "";
const rendererOrigin = developmentRenderer
  ? new URL(developmentRenderer).origin
  : localOrigin;
const persistentPartition = "persist:persome";
const globalAccelerator = "CommandOrControl+Shift+Space";
const preferenceDefaults = Object.freeze({
  sources: Object.freeze({ screenActivity: true, obsidian: true, appleApps: false }),
});

let mainWindow = null;
let quickWindow = null;
let tray = null;
let serverProcess = null;
let isQuitting = false;

function preferencesPath() {
  return path.join(app.getPath("userData"), "product-preferences.json");
}

async function loadPreferences() {
  try {
    const parsed = JSON.parse(await readFile(preferencesPath(), "utf8"));
    return {
      sources: {
        ...preferenceDefaults.sources,
        ...(parsed && typeof parsed.sources === "object" ? parsed.sources : {}),
      },
    };
  } catch {
    return { sources: { ...preferenceDefaults.sources } };
  }
}

async function savePreferences(preferences) {
  await writeFile(preferencesPath(), `${JSON.stringify(preferences, null, 2)}\n`, { mode: 0o600 });
}

function permissionStates() {
  if (process.platform !== "darwin") return {};
  return {
    microphone: systemPreferences.getMediaAccessStatus("microphone"),
    screen: systemPreferences.getMediaAccessStatus("screen"),
  };
}

function markdownExport(snapshot) {
  const name = snapshot?.model?.displayName || "My Personal Model";
  const faces = Array.isArray(snapshot?.personalModel?.faces) ? snapshot.personalModel.faces : [];
  const days = Array.isArray(snapshot?.time?.days) ? snapshot.time.days : [];
  return [
    `# ${name} · Persome export`,
    "",
    snapshot?.identity?.description || "",
    "",
    "## Current model",
    "",
    snapshot?.personalModel?.root || "Still forming.",
    "",
    ...faces.flatMap((face) => [`- ${face.text}`, `  - confidence: ${face.confidence}`, `  - observations: ${face.observations}`]),
    "",
    "## Rewind",
    "",
    ...days.flatMap((day) => [
      `### ${day.title}`,
      "",
      day.portrait || "",
      "",
      ...day.events.map((event) => `- ${event.time} · ${event.app || "Persome"} · ${event.title}`),
      "",
    ]),
  ].join("\n");
}

function rendererUrl(surface, route = "") {
  const base = developmentRenderer || `${localOrigin}/app/`;
  const url = new URL(base);
  url.searchParams.set("surface", surface);
  if (route) url.searchParams.set("route", route);
  return url.toString();
}

function isAllowedRendererUrl(value) {
  try {
    const url = new URL(value);
    return [localOrigin, rendererOrigin].includes(url.origin);
  } catch {
    return false;
  }
}

function isSafeExternalUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === "https:";
  } catch {
    return false;
  }
}

function secureWebPreferences() {
  return {
    preload: path.join(moduleRoot, "preload.cjs"),
    partition: persistentPartition,
    contextIsolation: true,
    nodeIntegration: false,
    sandbox: true,
    webSecurity: true,
    allowRunningInsecureContent: false,
    spellcheck: true,
  };
}

function protectWindow(window) {
  window.webContents.setWindowOpenHandler(({ url }) => {
    if (isSafeExternalUrl(url)) void shell.openExternal(url);
    return { action: "deny" };
  });
  window.webContents.on("will-navigate", (event, url) => {
    if (!isAllowedRendererUrl(url)) event.preventDefault();
  });
  window.webContents.on("will-attach-webview", (event) => event.preventDefault());
}

function createMainWindow(initialRoute = "home") {
  if (mainWindow && !mainWindow.isDestroyed()) return mainWindow;

  mainWindow = new BrowserWindow({
    title: "Persome",
    width: 1180,
    height: 820,
    minWidth: 760,
    minHeight: 560,
    show: false,
    // Dashboard is a Persome surface, not a macOS document window. Its own
    // draggable header replaces the native red/yellow/green window chrome.
    frame: false,
    backgroundColor: "#0a0b0e",
    vibrancy: "under-window",
    visualEffectState: "active",
    webPreferences: secureWebPreferences(),
  });
  mainWindow.setMenuBarVisibility(false);
  protectWindow(mainWindow);
  mainWindow.once("ready-to-show", () => mainWindow?.show());
  mainWindow.on("closed", () => {
    mainWindow = null;
  });
  void mainWindow.loadURL(rendererUrl("main", initialRoute));
  return mainWindow;
}

function positionQuickWindow() {
  if (!quickWindow || quickWindow.isDestroyed()) return;
  const display = screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
  const [width, height] = quickWindow.getSize();
  const x = Math.round(display.workArea.x + (display.workArea.width - width) / 2);
  const y = Math.round(display.workArea.y + Math.min(130, display.workArea.height * 0.14));
  quickWindow.setBounds({ x, y, width, height }, false);
}

function createQuickWindow() {
  if (quickWindow && !quickWindow.isDestroyed()) return quickWindow;

  quickWindow = new BrowserWindow({
    title: "Persome Quick Box",
    width: 720,
    height: 410,
    minWidth: 560,
    maxWidth: 840,
    show: false,
    frame: false,
    transparent: true,
    hasShadow: true,
    resizable: false,
    movable: true,
    alwaysOnTop: true,
    skipTaskbar: true,
    fullscreenable: false,
    backgroundColor: "#00000000",
    webPreferences: secureWebPreferences(),
  });
  quickWindow.setAlwaysOnTop(true, "pop-up-menu");
  quickWindow.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  protectWindow(quickWindow);
  quickWindow.on("blur", () => {
    if (!quickWindow?.webContents.isDevToolsOpened()) quickWindow?.hide();
  });
  quickWindow.on("closed", () => {
    quickWindow = null;
  });
  void quickWindow.loadURL(rendererUrl("quick"));
  return quickWindow;
}

function showMain(route = "home") {
  const hadWindow = Boolean(mainWindow && !mainWindow.isDestroyed());
  const window = createMainWindow(route);
  if (window.isMinimized()) window.restore();
  window.show();
  window.focus();
  // A newly-created Dashboard receives the target route in its first URL.
  // Existing Dashboards navigate through IPC without a page reload.
  if (hadWindow) window.webContents.send("persome:navigate", route);
}

function toggleQuickWindow() {
  const window = createQuickWindow();
  if (window.isVisible()) {
    window.hide();
    return;
  }
  showQuickWindow();
}

function showQuickWindow() {
  const window = createQuickWindow();
  positionQuickWindow();
  window.show();
  window.focus();
  window.webContents.send("persome:focus-input");
}

function createTrayIcon() {
  const svg = [
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18">',
    '<path fill="black" d="M9 1.4l1.35 4.4L14.6 4.1l-2.7 3.65 4.65.15-4.25 1.85 2.45 3.95-4.05-2.25L9 16l-1.7-4.55-4.05 2.25 2.45-3.95L1.45 7.9l4.65-.15L3.4 4.1l4.25 1.7L9 1.4z"/>',
    "</svg>",
  ].join("");
  const image = nativeImage.createFromDataURL(
    `data:image/svg+xml;base64,${Buffer.from(svg).toString("base64")}`,
  );
  image.setTemplateImage(true);
  return image;
}

function createTray() {
  tray = new Tray(createTrayIcon(), "02e66309-049f-4bcc-81e2-9b267c9425f1");
  tray.setToolTip("Persome · Your Personal Model");
  tray.setIgnoreDoubleClickEvents(true);
  tray.on("click", toggleQuickWindow);
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: "Open Quick Box", accelerator: globalAccelerator, click: toggleQuickWindow },
    { label: "Open Persome", click: () => showMain("home") },
    { type: "separator" },
    { label: "Map", click: () => showMain("map") },
    { label: "Connected AI", click: () => showMain("swipe") },
    { label: "Trust & Permissions", click: () => showMain("settings") },
    { type: "separator" },
    { role: "quit", label: "Quit Persome" },
  ]));
}

async function probeServer() {
  try {
    const response = await fetch(`${localOrigin}/api/app/health`, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(800),
    });
    if (!response.ok) return false;
    const health = await response.json();
    return health?.ok === true && health?.desktopRenderer === "electron-v1";
  } catch {
    return false;
  }
}

async function startServer() {
  if (await probeServer()) return;
  const serverPath = path.join(serverRoot, "persome-card-server.mjs");
  serverProcess = utilityProcess.fork(serverPath, [], {
    cwd: serverRoot,
    env: {
      ...process.env,
      NODE_ENV: app.isPackaged ? "production" : "development",
      WHOAMI_DEV_MODE: app.isPackaged ? "0" : (process.env.WHOAMI_DEV_MODE || "1"),
      WHOAMI_CARD_PORT: serverPort,
      WHOAMI_CARD_DATA_DIR: process.env.WHOAMI_CARD_DATA_DIR || app.getPath("userData"),
      WHOAMI_PRODUCT_VERSION: app.getVersion(),
    },
    stdio: "pipe",
    serviceName: "Persome Local Service",
  });
  serverProcess.stdout?.on("data", (chunk) => {
    if (!app.isPackaged) process.stdout.write(chunk);
  });
  serverProcess.stderr?.on("data", (chunk) => {
    if (!app.isPackaged) process.stderr.write(chunk);
  });
  for (let attempt = 0; attempt < 120; attempt += 1) {
    if (await probeServer()) return;
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error("Persome local service did not become ready.");
}

function assertTrustedSender(event) {
  if (!isAllowedRendererUrl(event.senderFrame.url)) {
    throw new Error("Untrusted Persome renderer.");
  }
}

function installIpcHandlers() {
  ipcMain.on("persome:open-main", (event, route) => {
    assertTrustedSender(event);
    showMain(typeof route === "string" ? route : "home");
    quickWindow?.hide();
  });
  ipcMain.on("persome:close-quick", (event) => {
    assertTrustedSender(event);
    quickWindow?.hide();
  });
  ipcMain.handle("persome:shell-state", (event) => {
    assertTrustedSender(event);
    return Object.freeze({
      platform: process.platform,
      packaged: app.isPackaged,
      globalShortcut: globalAccelerator,
    });
  });
  ipcMain.handle("persome:get-preferences", async (event) => {
    assertTrustedSender(event);
    const preferences = await loadPreferences();
    return Object.freeze({ ...preferences, permissions: permissionStates() });
  });
  ipcMain.handle("persome:set-source-enabled", async (event, source, enabled) => {
    assertTrustedSender(event);
    if (!["screenActivity", "obsidian", "appleApps"].includes(source)) {
      throw new Error("Unknown Persome source.");
    }
    const preferences = await loadPreferences();
    preferences.sources[source] = Boolean(enabled);
    await savePreferences(preferences);
    return preferences.sources[source];
  });
  ipcMain.handle("persome:open-system-permission", async (event, permission) => {
    assertTrustedSender(event);
    const destinations = {
      screen: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
      microphone: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
      accessibility: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
    };
    const destination = destinations[permission];
    if (!destination) throw new Error("Unknown macOS permission.");
    await shell.openExternal(destination);
    return true;
  });
  ipcMain.handle("persome:export-snapshot", async (event, format, snapshot) => {
    assertTrustedSender(event);
    if (!["markdown", "json"].includes(format)) throw new Error("Unknown export format.");
    const extension = format === "markdown" ? "md" : "json";
    const result = await dialog.showSaveDialog(mainWindow || BrowserWindow.fromWebContents(event.sender), {
      title: "Export your Personal Model",
      defaultPath: `Persome-export.${extension}`,
      filters: [{ name: format === "markdown" ? "Markdown" : "JSON", extensions: [extension] }],
    });
    if (result.canceled || !result.filePath) return { canceled: true };
    const contents = format === "markdown"
      ? markdownExport(snapshot)
      : `${JSON.stringify(snapshot, null, 2)}\n`;
    await writeFile(result.filePath, contents, { mode: 0o600 });
    return { canceled: false, path: result.filePath };
  });
  ipcMain.handle("persome:open-external", async (event, url) => {
    assertTrustedSender(event);
    if (!isSafeExternalUrl(url)) throw new Error("Only HTTPS links can be opened.");
    await shell.openExternal(url);
    return true;
  });
}

function createApplicationMenu() {
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    {
      label: "Persome",
      submenu: [
        { role: "about", label: "About Persome" },
        { type: "separator" },
        { label: "Open Quick Box", accelerator: globalAccelerator, click: toggleQuickWindow },
        { label: "Trust & Permissions…", accelerator: "CommandOrControl+,", click: () => showMain("settings") },
        { type: "separator" },
        { role: "hide" },
        { role: "hideOthers" },
        { role: "unhide" },
        { type: "separator" },
        { role: "quit", label: "Quit Persome" },
      ],
    },
    { role: "editMenu" },
    { role: "windowMenu" },
  ]));
}

const gotSingleInstanceLock = app.requestSingleInstanceLock();
app.enableSandbox();
if (!gotSingleInstanceLock) {
  app.quit();
} else {
  app.on("second-instance", showQuickWindow);
  app.on("before-quit", () => {
    isQuitting = true;
  });
  app.on("will-quit", () => {
    globalShortcut.unregisterAll();
    serverProcess?.kill();
  });
  app.on("window-all-closed", () => {
    if (process.platform !== "darwin" && isQuitting) app.quit();
  });
  app.on("activate", showQuickWindow);

  app.whenReady().then(async () => {
    app.setName("Persome");
    app.setAppUserModelId("ai.intuition.persome");
    app.setAboutPanelOptions({
      applicationName: "Persome",
      applicationVersion: app.getVersion(),
      copyright: "© Intuition Lab",
    });
    session.fromPartition(persistentPartition).setPermissionRequestHandler(
      (webContents, permission, callback) => callback(
        isAllowedRendererUrl(webContents.getURL()) && permission === "media",
      ),
    );
    installIpcHandlers();
    createApplicationMenu();
    await startServer();
    createQuickWindow();
    createTray();
    globalShortcut.register(globalAccelerator, toggleQuickWindow);
    showQuickWindow();
  }).catch((error) => {
    console.error(error);
    app.quit();
  });
}
