import { installAndroidVisualViewportSync } from "./android-visual-viewport";

type CapacitorLifecycleBridge = {
  triggerEvent?: (...args: unknown[]) => void;
};

const remoteWindow = window as Window & { Capacitor?: CapacitorLifecycleBridge };
const userAgent = navigator.userAgent;
const isAndroidWebView =
  /Android/i.test(userAgent) &&
  (/\bwv\b/i.test(userAgent) || /CodexLocalRemoteAndroidShell/i.test(userAgent));
const isIOSShell = /CodexLocalRemoteIOSShell/i.test(userAgent);
const isMacCatalystShell =
  (isIOSShell || /CodexLocalRemoteMobileShell/i.test(userAgent)) &&
  /(Macintosh|MacIntel)/i.test(userAgent);

if (isAndroidWebView) {
  document.documentElement.dataset.androidWebview = "true";
  installAndroidVisualViewportSync();
}

if (isIOSShell) {
  document.documentElement.dataset.iosShell = "true";
}

if (isMacCatalystShell) {
  document.documentElement.dataset.macCatalyst = "true";
}

// A remote page is hosted outside the Capacitor origin, but the native shell may
// still send lifecycle events after returning from the background. Keep that
// compatibility call harmless when the Capacitor runtime is not present.
if (!remoteWindow.Capacitor) remoteWindow.Capacitor = {};
if (typeof remoteWindow.Capacitor.triggerEvent !== "function") {
  remoteWindow.Capacitor.triggerEvent = () => {};
}

try {
  if (window.localStorage.getItem("codex-local-remote:locale") === "en") {
    document.documentElement.lang = "en";
    const manifest = document.getElementById("web-manifest");
    if (manifest) manifest.setAttribute("href", "./manifest-en.webmanifest");
  }
} catch {
  // Stored locale is best effort; the application applies its default below.
}

const showFatalError = (reason: unknown) => {
  if (document.getElementById("web-runtime-error")) return;
  const panel = document.createElement("pre");
  panel.id = "web-runtime-error";
  panel.style.cssText =
    "position:fixed;inset:16px;z-index:2147483647;overflow:auto;margin:0;padding:16px;border:1px solid #dc2626;background:#fff7f7;color:#991b1b;white-space:pre-wrap;font:14px/1.6 sans-serif";
  const isEnglish = document.documentElement.lang.toLowerCase().startsWith("en");
  const error = reason as { stack?: string; message?: string } | null;
  panel.textContent =
    (isEnglish
      ? "The page failed to run. Send the information below to the developer:\n\n"
      : "页面运行失败，请把下面信息发给开发者：\n\n") +
    (error && (error.stack || error.message) ? error.stack || error.message : String(reason));
  document.body.appendChild(panel);
};

window.addEventListener("error", (event) => showFatalError(event.error || event.message));
window.addEventListener("unhandledrejection", (event) => showFatalError(event.reason));
