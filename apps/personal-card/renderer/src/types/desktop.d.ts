export {};

declare global {
  interface Window {
    persomeDesktop?: Readonly<{
      closeQuick: () => void;
      getShellState: () => Promise<{
        platform: string;
        packaged: boolean;
        globalShortcut: string;
      }>;
      getPreferences: () => Promise<{
        sources: Record<string, boolean>;
        permissions: Record<string, string>;
      }>;
      setSourceEnabled: (source: string, enabled: boolean) => Promise<boolean>;
      openSystemPermission: (permission: string) => Promise<boolean>;
      exportSnapshot: (format: "markdown" | "json", snapshot: unknown) => Promise<{ canceled: boolean; path?: string }>;
      openExternal: (url: string) => Promise<boolean>;
      openMain: (route?: string) => void;
      onFocusInput: (listener: () => void) => () => void;
      onNavigate: (listener: (route: string) => void) => () => void;
    }>;
  }
}
