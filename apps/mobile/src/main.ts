const storageKey = "codex-local-remote.mobile.server-url";
const draftStorageKey = "codex-local-remote.mobile.server-url-draft";
const attemptStorageKey = "codex-local-remote.mobile.connection-attempt";
const form = document.querySelector<HTMLFormElement>("#connection-form");
const input = document.querySelector<HTMLInputElement>("#server-url");
const error = document.querySelector<HTMLElement>("#connection-error");
const statusMessage = document.querySelector<HTMLElement>("#connection-status");
const clearButton = document.querySelector<HTMLButtonElement>("#clear-connection");
const saveButton = document.querySelector<HTMLButtonElement>("#save-connection");
const languageButton = document.querySelector<HTMLButtonElement>("#toggle-language");
const stopAutoConnectButton = document.querySelector<HTMLButtonElement>("#stop-auto-connect");
const currentTime = document.querySelector<HTMLElement>("#current-time");
let navigationTimer: number | undefined;
let autoConnectTimer: number | undefined;
let autoConnectCountdownTimer: number | undefined;
const autoConnectDelaySeconds = 3;

const isMacCatalystShell =
  /CodexLocalRemoteMobileShell/i.test(navigator.userAgent) &&
  /(Macintosh|MacIntel)/i.test(navigator.userAgent);

if (isMacCatalystShell) {
  document.documentElement.dataset.macCatalyst = "true";
}

type WebView2Runtime = {
  postMessage?: (message: string) => void;
};

function webView2Runtime(): WebView2Runtime | undefined {
  return (window as Window & { chrome?: { webview?: WebView2Runtime } }).chrome?.webview;
}

function requestWindowsConnection(serverUrl: string): boolean {
  const webView2 = webView2Runtime();
  if (!webView2?.postMessage) return false;
  webView2.postMessage(JSON.stringify({ type: "connect", url: serverUrl }));
  return true;
}

type MobileLocale = "zh" | "en";
type LocalizedMessage = () => string;

const localeStorageKey = "codex-local-remote:locale";
const staticCopy: Record<MobileLocale, Record<string, string>> = {
  zh: {
    eyebrow: "独立手机版",
    title: "连接到你的电脑",
    description: "填写 Sidecar 的完整访问地址。保存后立即连接，下次启动会自动使用这个地址。",
    addressLabel: "连接地址",
    placeholder: "https://主机/codex-remote/",
    loadingStatus: "正在载入操作功能…",
    save: "保存并连接",
    clear: "清除已保存地址",
    note: "HTTP 仅限本机和局域网地址。公网连接请使用 HTTPS。",
    languageButton: "EN",
    languageButtonAria: "切换到英文",
    stopAutoConnect: "停止自动连接",
    stopAutoConnectAria: "停止自动连接",
    timeAria: "当前时间",
  },
  en: {
    eyebrow: "Mobile app",
    title: "Connect to your computer",
    description:
      "Enter the complete Sidecar address. It connects after saving and is reused next time.",
    addressLabel: "Connection address",
    placeholder: "https://host/codex-remote/",
    loadingStatus: "Loading controls…",
    save: "Save and connect",
    clear: "Clear saved address",
    note: "HTTP is limited to this computer and the local network. Use HTTPS for public access.",
    languageButton: "中",
    languageButtonAria: "Switch to Chinese",
    stopAutoConnect: "Stop auto-connect",
    stopAutoConnectAria: "Stop automatic connection",
    timeAria: "Current time",
  },
};

function readMobileLocale(): MobileLocale {
  try {
    const stored = window.localStorage.getItem(localeStorageKey);
    if (stored === "en" || stored === "zh") return stored;
  } catch {
    // Locale persistence is best effort.
  }
  return navigator.language.toLowerCase().startsWith("en") ? "en" : "zh";
}

let locale = readMobileLocale();
let activeErrorMessage: LocalizedMessage | undefined;
let activeStatusMessage: LocalizedMessage | undefined;

function currentText(zh: string, en: string): string {
  return locale === "en" ? en : zh;
}

function localMessage(zh: string, en: string): LocalizedMessage {
  return () => currentText(zh, en);
}

function copy(key: string): string {
  return staticCopy[locale][key] ?? key;
}

function applyLocale(): void {
  document.documentElement.lang = locale === "zh" ? "zh-Hans" : "en";
  document.title = "Codex Local Remote";

  document.querySelectorAll<HTMLElement>("[data-i18n]").forEach((element) => {
    const key = element.dataset.i18n;
    if (key) element.textContent = copy(key);
  });
  const placeholder = document.querySelector<HTMLInputElement>("[data-i18n-placeholder]");
  if (placeholder) placeholder.placeholder = copy("placeholder");
  if (currentTime) currentTime.setAttribute("aria-label", copy("timeAria"));
  if (languageButton) {
    languageButton.textContent = copy("languageButton");
    languageButton.setAttribute("aria-label", copy("languageButtonAria"));
  }
  if (stopAutoConnectButton) {
    stopAutoConnectButton.textContent = copy("stopAutoConnect");
    stopAutoConnectButton.setAttribute("aria-label", copy("stopAutoConnectAria"));
  }
  updateCurrentTime();
  if (activeErrorMessage && error) error.textContent = activeErrorMessage();
  if (activeStatusMessage && statusMessage) statusMessage.textContent = activeStatusMessage();
}

function setLocale(nextLocale: MobileLocale): void {
  locale = nextLocale;
  try {
    window.localStorage.setItem(localeStorageKey, locale);
  } catch {
    // Locale persistence is best effort.
  }
  applyLocale();
}

function updateCurrentTime(): void {
  if (!currentTime) return;
  currentTime.textContent = new Date().toLocaleTimeString(locale === "en" ? "en-US" : "zh-CN", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });
}

updateCurrentTime();
window.setInterval(updateCurrentTime, 1000);

function isPrivateIpv4(hostname: string): boolean {
  const octets = hostname.split(".").map(Number);
  if (octets.length !== 4 || octets.some((value) => !Number.isInteger(value))) return false;
  const [first = -1, second = -1] = octets;
  return (
    first === 10 ||
    first === 127 ||
    (first === 169 && second === 254) ||
    (first === 172 && second >= 16 && second <= 31) ||
    (first === 192 && second === 168)
  );
}

function isLocalHost(hostname: string): boolean {
  const normalized = hostname.toLowerCase().replace(/^\[|\]$/g, "");
  return (
    normalized === "localhost" ||
    normalized.endsWith(".localhost") ||
    normalized.endsWith(".local") ||
    normalized === "::1" ||
    normalized.startsWith("fc") ||
    normalized.startsWith("fd") ||
    /^fe[89ab]/.test(normalized) ||
    isPrivateIpv4(normalized)
  );
}

function normalizeServerUrl(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) throw new Error(currentText("请输入连接地址。", "Enter a connection address."));

  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    throw new Error(
      currentText(
        "连接地址格式不正确，请填写完整地址，例如 http://192.168.1.10:8787/。",
        "The connection address is invalid. Enter a complete address such as http://192.168.1.10:8787/.",
      ),
    );
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new Error(
      currentText(
        "连接地址必须使用 HTTPS 或 HTTP。",
        "The connection address must use HTTPS or HTTP.",
      ),
    );
  }
  if (url.username || url.password || url.search || url.hash) {
    throw new Error(
      currentText(
        "连接地址中不能包含账号、密码、查询参数或片段。",
        "The connection address cannot contain credentials, query parameters, or a fragment.",
      ),
    );
  }
  if (url.protocol === "http:" && !isLocalHost(url.hostname)) {
    throw new Error(
      currentText(
        "HTTP 仅允许本机或局域网地址；其他地址请使用 HTTPS。",
        "HTTP is allowed only for this computer or the local network; use HTTPS for other addresses.",
      ),
    );
  }
  if (!url.pathname.endsWith("/")) url.pathname += "/";
  return url.toString();
}

function showError(message: string | LocalizedMessage): void {
  activeErrorMessage = typeof message === "function" ? message : () => message;
  if (!error) return;
  error.textContent = activeErrorMessage();
  error.hidden = error.textContent === "";
}

function showStatus(message: string | LocalizedMessage): void {
  activeStatusMessage = typeof message === "function" ? message : () => message;
  if (!statusMessage) return;
  statusMessage.textContent = activeStatusMessage();
  statusMessage.hidden = statusMessage.textContent === "";
}

function getNativeConfigureParameters(): URLSearchParams | undefined {
  const marker = "#configure?";
  const hash = window.location.hash;
  if (!hash.startsWith(marker)) return undefined;
  return new URLSearchParams(hash.slice(marker.length));
}

function getNativeConnectionError(): LocalizedMessage | undefined {
  const params = getNativeConfigureParameters();
  if (!params) return undefined;

  switch (params.get("error")) {
    case "ssl":
      return localMessage(
        "无法建立 HTTPS 安全连接。请确认使用的是证书对应的域名，不要用 IP 地址替代域名；自签名证书需要先在 Android 系统中信任。",
        "Unable to establish a secure HTTPS connection. Use the certificate's domain instead of its IP address; Android must trust self-signed certificates first.",
      );
    case "cleartext":
      return localMessage(
        "Android 拒绝了这个 HTTP 明文连接。请改用 HTTPS，或确认使用的是支持局域网 HTTP 的最新应用。",
        "Android rejected this cleartext HTTP connection. Use HTTPS, or install a current app build that supports local-network HTTP.",
      );
    case "http": {
      const status = params.get("status");
      return status
        ? () =>
            currentText(
              `服务器返回了 HTTP ${status} 错误。请检查访问路径、反向代理和端口。`,
              `The server returned HTTP ${status}. Check the path, reverse proxy, and port.`,
            )
        : localMessage(
            "服务器返回了 HTTP 错误。请检查访问路径、反向代理和端口。",
            "The server returned an HTTP error. Check the path, reverse proxy, and port.",
          );
    }
    case "network":
      return localMessage(
        "无法连接到这个地址。请确认电脑端 Sidecar 已启动、手机与电脑网络互通，并检查地址和端口。",
        "Unable to connect to this address. Make sure Sidecar is running, the phone can reach the computer, and the address and port are correct.",
      );
    default:
      return localMessage(
        "无法打开这个地址。请检查地址、端口以及手机与电脑之间的网络连接。",
        "Unable to open this address. Check the address, port, and network connection between the phone and computer.",
      );
  }
}

function getNativeConnectionUrl(): string | undefined {
  const value = getNativeConfigureParameters()?.get("url");
  if (!value) return undefined;
  try {
    return normalizeServerUrl(value);
  } catch {
    return undefined;
  }
}

languageButton?.addEventListener("click", () => {
  setLocale(locale === "zh" ? "en" : "zh");
});

applyLocale();

const rawSavedUrl = window.localStorage.getItem(storageKey) ?? "";
let draftUrl = window.localStorage.getItem(draftStorageKey) ?? "";
let savedUrl = "";
let savedUrlError: LocalizedMessage | undefined;

if (rawSavedUrl) {
  try {
    savedUrl = normalizeServerUrl(rawSavedUrl);
  } catch {
    savedUrlError = localMessage(
      "之前保存的连接地址无效，请检查地址后重新连接。",
      "The previously saved connection address is invalid. Check it and connect again.",
    );
    if (!draftUrl) draftUrl = rawSavedUrl;
    window.localStorage.setItem(draftStorageKey, draftUrl);
    window.localStorage.removeItem(storageKey);
  }
}

const nativeConnectionError = getNativeConnectionError();
const nativeConnectionUrl = getNativeConnectionUrl();
if (nativeConnectionUrl) {
  draftUrl = nativeConnectionUrl;
  window.localStorage.setItem(draftStorageKey, draftUrl);
}
const editing =
  window.location.hash === "#configure" || window.location.hash.startsWith("#configure?");
const previousAttempt = Number(window.sessionStorage.getItem(attemptStorageKey) ?? "0");
const returnedFromFailedAttempt = Date.now() - previousAttempt < 30_000;
const windowsShell = Boolean(webView2Runtime()?.postMessage);
if (windowsShell) {
  window.localStorage.removeItem(storageKey);
}

const displayedUrl = editing ? draftUrl || savedUrl : savedUrl || draftUrl;
if (input) input.value = displayedUrl;

function clearAutomaticConnectionTimers(): void {
  if (autoConnectTimer !== undefined) {
    window.clearTimeout(autoConnectTimer);
    autoConnectTimer = undefined;
  }
  if (autoConnectCountdownTimer !== undefined) {
    window.clearInterval(autoConnectCountdownTimer);
    autoConnectCountdownTimer = undefined;
  }
}

function stopAutomaticConnection(showMessage = true): void {
  clearAutomaticConnectionTimers();
  if (stopAutoConnectButton) stopAutoConnectButton.hidden = true;
  window.sessionStorage.removeItem(attemptStorageKey);
  if (showMessage) {
    showStatus(
      localMessage(
        "已停止自动连接，可以修改地址后重新连接。",
        "Automatic connection stopped. You can change the address and connect again.",
      ),
    );
  }
}

function startAutomaticConnection(): void {
  if (!savedUrl) return;
  let remainingSeconds = autoConnectDelaySeconds;
  if (stopAutoConnectButton) stopAutoConnectButton.hidden = false;
  const updateCountdown = () => {
    showStatus(() =>
      currentText(
        `${remainingSeconds} 秒后自动连接，可点击右上角停止。`,
        `Connecting automatically in ${remainingSeconds} seconds. Tap Stop to cancel.`,
      ),
    );
  };
  updateCountdown();
  autoConnectCountdownTimer = window.setInterval(() => {
    remainingSeconds -= 1;
    if (remainingSeconds > 0) updateCountdown();
  }, 1000);
  autoConnectTimer = window.setTimeout(() => {
    clearAutomaticConnectionTimers();
    if (stopAutoConnectButton) stopAutoConnectButton.hidden = true;
    window.sessionStorage.setItem(attemptStorageKey, String(Date.now()));
    window.location.assign(savedUrl);
  }, autoConnectDelaySeconds * 1000);
}

stopAutoConnectButton?.addEventListener("click", () => stopAutomaticConnection());

const shouldAutoConnect = !windowsShell && savedUrl && !editing && !returnedFromFailedAttempt;
if (shouldAutoConnect) {
  startAutomaticConnection();
} else {
  window.sessionStorage.removeItem(attemptStorageKey);
  document.documentElement.dataset.mobileShell = "ready";
  if (nativeConnectionError) {
    showError(nativeConnectionError);
  } else if (savedUrlError) {
    showError(savedUrlError);
  } else if (returnedFromFailedAttempt) {
    showError(
      localMessage(
        "未能打开这个地址。请确认电脑端 Sidecar 已启动、手机与电脑网络互通，并检查地址和端口。",
        "Unable to open this address. Make sure Sidecar is running, the phone can reach the computer, and the address and port are correct.",
      ),
    );
  }
}

if (!shouldAutoConnect) {
  showStatus(localMessage("操作功能已就绪。", "Controls are ready."));
}

input?.addEventListener("input", () => {
  if (autoConnectTimer !== undefined) stopAutomaticConnection(false);
  window.localStorage.setItem(draftStorageKey, input.value);
  showError("");
  showStatus("");
});

form?.addEventListener("submit", (event) => {
  event.preventDefault();
  stopAutomaticConnection(false);
  if (navigationTimer !== undefined) window.clearTimeout(navigationTimer);
  showError("");
  showStatus(localMessage("正在检查连接地址…", "Checking the connection address…"));
  const enteredUrl = input?.value ?? "";
  window.localStorage.setItem(draftStorageKey, enteredUrl);
  try {
    const serverUrl = normalizeServerUrl(enteredUrl);
    window.localStorage.setItem(draftStorageKey, serverUrl);
    showStatus(localMessage("正在连接…", "Connecting…"));
    if (saveButton) {
      saveButton.disabled = true;
      saveButton.textContent = currentText("正在连接…", "Connecting…");
    }

    if (requestWindowsConnection(serverUrl)) {
      return;
    }

    window.localStorage.setItem(storageKey, serverUrl);
    window.sessionStorage.setItem(attemptStorageKey, String(Date.now()));
    navigationTimer = window.setTimeout(() => {
      window.location.assign(serverUrl);
      navigationTimer = window.setTimeout(() => {
        if (saveButton) {
          saveButton.disabled = false;
          saveButton.textContent = copy("save");
        }
        showStatus("");
        showError(
          localMessage(
            "未能打开这个地址。请确认电脑端 Sidecar 已启动、手机与电脑网络互通，并检查地址和端口。",
            "Unable to open this address. Make sure Sidecar is running, the phone can reach the computer, and the address and port are correct.",
          ),
        );
      }, 8000);
    }, 120);
  } catch (validationError) {
    showStatus("");
    const message =
      validationError instanceof Error
        ? validationError.message
        : currentText("连接地址无效。", "The connection address is invalid.");
    showError(currentText(`保存失败：${message}`, `Save failed: ${message}`));
    input?.focus();
  }
});

clearButton?.addEventListener("click", () => {
  stopAutomaticConnection(false);
  window.localStorage.removeItem(storageKey);
  window.localStorage.removeItem(draftStorageKey);
  if (input) input.value = "";
  showError("");
  showStatus(localMessage("已清除保存的连接地址。", "The saved connection address was cleared."));
  input?.focus();
});
