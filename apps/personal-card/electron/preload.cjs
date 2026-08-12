const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("persomeDesktop", Object.freeze({
  closeQuick: () => ipcRenderer.send("persome:close-quick"),
  getShellState: () => ipcRenderer.invoke("persome:shell-state"),
  getPreferences: () => ipcRenderer.invoke("persome:get-preferences"),
  setSourceEnabled: (source, enabled) => ipcRenderer.invoke("persome:set-source-enabled", String(source), Boolean(enabled)),
  openSystemPermission: (permission) => ipcRenderer.invoke("persome:open-system-permission", String(permission)),
  exportSnapshot: (format, snapshot) => ipcRenderer.invoke("persome:export-snapshot", String(format), snapshot),
  openExternal: (url) => ipcRenderer.invoke("persome:open-external", String(url)),
  openMain: (route = "home") => ipcRenderer.send("persome:open-main", String(route)),
  onFocusInput: (listener) => {
    const wrapped = () => listener();
    ipcRenderer.on("persome:focus-input", wrapped);
    return () => ipcRenderer.removeListener("persome:focus-input", wrapped);
  },
  onNavigate: (listener) => {
    const wrapped = (_event, route) => listener(String(route));
    ipcRenderer.on("persome:navigate", wrapped);
    return () => ipcRenderer.removeListener("persome:navigate", wrapped);
  },
}));
