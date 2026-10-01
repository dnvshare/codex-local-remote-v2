type CapacitorRuntime = {
  getServerUrl?: () => string;
  isNativePlatform?: () => boolean;
};

type WebView2Runtime = {
  postMessage?: (message: string) => void;
};

function capacitorRuntime(): CapacitorRuntime | undefined {
  return (window as Window & { Capacitor?: CapacitorRuntime }).Capacitor;
}

function webView2Runtime(): WebView2Runtime | undefined {
  return (window as Window & { chrome?: { webview?: WebView2Runtime } }).chrome?.webview;
}

export function notifyNativeAuthenticated(): void {
  const webView2 = webView2Runtime();
  if (!webView2?.postMessage) return;
  webView2.postMessage(
    JSON.stringify({
      type: "authenticated",
      url: new URL(".", window.location.href).href,
    }),
  );
}

export function notifyNativeAuthenticationRequired(): void {
  const webView2 = webView2Runtime();
  if (!webView2?.postMessage) return;
  webView2.postMessage(JSON.stringify({ type: "authentication-required" }));
}

export function nativeShellVoiceInputEnabled(
  userAgent = typeof navigator === "undefined" ? "" : navigator.userAgent,
): boolean {
  const isAndroidShell =
    /Android/i.test(userAgent) &&
    (/\bwv\b/i.test(userAgent) || /CodexLocalRemoteAndroidShell/i.test(userAgent));
  const isIOSShell = /CodexLocalRemoteIOSShell/i.test(userAgent);
  const isMacCatalystShell = isIOSShell && /(Macintosh|MacIntel)/i.test(userAgent);
  return !isAndroidShell && (!isIOSShell || isMacCatalystShell);
}

export function isNativeMobileShell(): boolean {
  return (
    capacitorRuntime()?.isNativePlatform?.() === true || Boolean(webView2Runtime()?.postMessage)
  );
}

export function openMobileConnectionSettings(): void {
  const webView2 = webView2Runtime();
  if (webView2?.postMessage) {
    webView2.postMessage("open-connection-settings");
    return;
  }

  const shellUrl = capacitorRuntime()?.getServerUrl?.();
  if (shellUrl) window.location.assign(`${shellUrl.replace(/\/$/, "")}#configure`);
}
