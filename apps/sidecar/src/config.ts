import { readFileSync } from "node:fs";
import { isIP } from "node:net";
import os from "node:os";
import path from "node:path";

import { normalizeLoopbackWebSocketEndpoint } from "@codex-local-remote/app-server-client";

export type SidecarSecurityMode = "https" | "insecure-http";

const DEFAULT_SESSION_COOKIE_NAME = "codex_remote_session";
const SESSION_COOKIE_NAME_PATTERN = /^[A-Za-z][A-Za-z0-9_-]{0,63}$/u;

export interface SidecarAuthSettings {
  minimumPasswordLength: number;
  sessionAbsoluteTtlMs: number;
  sessionIdleTtlMs: number;
  loginSourceMaxAttempts: number;
  loginGlobalMaxAttempts: number;
  loginWindowMs: number;
  loginLockoutMs: number;
}

export interface SidecarConfig {
  appServerUrl: string;
  host: "0.0.0.0" | "127.0.0.1" | "::1";
  port: number;
  basePath: string;
  sessionCookieName: string;
  codexPath?: string;
  dataDir: string;
  desktopSyncEnabled: boolean;
  maintenanceTokenFile?: string;
  securityMode: SidecarSecurityMode;
  allowedOrigins: readonly string[];
  trustedProxyAddresses: readonly string[];
  trustedProxyNetworks: readonly string[];
  auth: SidecarAuthSettings;
  webDir: string;
}

export interface SidecarConfigOverrides {
  appServerUrl?: string;
  host?: string;
  port?: number;
  basePath?: string;
  codexPath?: string;
  dataDir?: string;
  desktopSyncEnabled?: boolean;
  maintenanceTokenFile?: string;
  securityMode?: string;
  webDir?: string;
}

export interface ResolveSidecarConfigOptions {
  cli?: SidecarConfigOverrides;
  environment?: Record<string, string | undefined>;
}

export type CliInvocation =
  | { command: "help" }
  | { command: "serve"; config: SidecarConfigOverrides }
  | { command: "setup-password"; config: Pick<SidecarConfigOverrides, "dataDir"> }
  | {
      command: "register-project";
      config: Pick<SidecarConfigOverrides, "dataDir">;
      project: { id: string; name: string; root: string };
    };

export function resolveSidecarConfig(options: ResolveSidecarConfigOptions = {}): SidecarConfig {
  const environment = options.environment ?? process.env;
  const cli = options.cli ?? {};
  const localAppData =
    environment.LOCALAPPDATA ?? path.win32.join(os.homedir(), "AppData", "Local");
  const dataDir = path.win32.resolve(
    cli.dataDir ??
      environment.CODEX_REMOTE_V2_DATA_DIR ??
      path.win32.join(localAppData, "CodexLocalRemoteV2"),
  );
  const remoteSettings = loadRemoteSettings(dataDir);
  const host = normalizeListenHost(
    cli.host ?? remoteSettings.listenMode ?? environment.CODEX_REMOTE_V2_HOST ?? "lan",
  );
  const basePath = normalizeBasePath(
    cli.basePath ??
      remoteSettings.basePath ??
      environment.CODEX_REMOTE_V2_BASE_PATH ??
      "/codex-remote",
  );
  const port =
    cli.port ?? remoteSettings.sidecarPort ?? parsePort(environment.CODEX_REMOTE_V2_PORT) ?? 28_790;
  if (!Number.isSafeInteger(port) || port < 1 || port > 65_535) {
    throw new Error("Invalid Sidecar port");
  }

  const codexPathValue = cli.codexPath ?? environment.CODEX_REMOTE_V2_CODEX_PATH;
  const codexPath =
    codexPathValue === undefined || codexPathValue.length === 0
      ? undefined
      : path.win32.resolve(codexPathValue);
  const webDir =
    cli.webDir ??
    environment.CODEX_REMOTE_V2_WEB_DIR ??
    path.resolve(import.meta.dirname, "../../web/dist");
  const desktopSyncEnabled =
    cli.desktopSyncEnabled ??
    remoteSettings.desktopSyncEnabled ??
    parseBooleanSwitch(environment.CODEX_REMOTE_V2_DESKTOP_SYNC) ??
    true;
  const securityMode = normalizeSecurityMode(
    cli.securityMode ??
      remoteSettings.securityMode ??
      environment.CODEX_REMOTE_V2_SECURITY_MODE ??
      "https",
  );
  const maintenanceTokenFile = normalizeLocalMaintenanceTokenFile(
    cli.maintenanceTokenFile ?? environment.CODEX_REMOTE_V2_MAINTENANCE_TOKEN_FILE,
  );
  const appServerUrl = normalizeLoopbackWebSocketEndpoint(
    cli.appServerUrl ??
      environment.CODEX_REMOTE_V2_APP_SERVER_WS_URL ??
      environment.CODEX_APP_SERVER_WS_URL ??
      (remoteSettings.brokerPort === undefined
        ? undefined
        : `ws://127.0.0.1:${remoteSettings.brokerPort}`) ??
      "ws://127.0.0.1:28791",
  );
  const trustedProxies =
    remoteSettings.trustedProxyAddresses !== undefined ||
    remoteSettings.trustedProxyNetworks !== undefined
      ? {
          addresses: remoteSettings.trustedProxyAddresses ?? [],
          networks: remoteSettings.trustedProxyNetworks ?? [],
        }
      : loadTrustedProxies(dataDir);

  return {
    appServerUrl,
    basePath,
    sessionCookieName: remoteSettings.sessionCookieName,
    ...(codexPath === undefined ? {} : { codexPath }),
    dataDir,
    desktopSyncEnabled,
    host,
    ...(maintenanceTokenFile === undefined ? {} : { maintenanceTokenFile }),
    port,
    securityMode,
    allowedOrigins: remoteSettings.allowedOrigins,
    trustedProxyAddresses: trustedProxies.addresses,
    trustedProxyNetworks: trustedProxies.networks,
    auth: remoteSettings.auth,
    webDir,
  };
}

interface LoadedRemoteSettings {
  allowedOrigins: readonly string[];
  auth: SidecarAuthSettings;
  basePath?: string;
  brokerPort?: number;
  desktopSyncEnabled?: boolean;
  listenMode?: string;
  sessionCookieName: string;
  securityMode?: string;
  sidecarPort?: number;
  trustedProxyAddresses?: readonly string[];
  trustedProxyNetworks?: readonly string[];
  upstreamPort?: number;
}

const DEFAULT_REMOTE_AUTH_SETTINGS: SidecarAuthSettings = {
  minimumPasswordLength: 15,
  sessionAbsoluteTtlMs: 7 * 24 * 60 * 60 * 1_000,
  sessionIdleTtlMs: 24 * 60 * 60 * 1_000,
  loginSourceMaxAttempts: 5,
  loginGlobalMaxAttempts: 50,
  loginWindowMs: 10 * 60_000,
  loginLockoutMs: 15 * 60_000,
};

function loadRemoteSettings(dataDir: string): LoadedRemoteSettings {
  const file = path.win32.join(dataDir, "remote-settings.json");
  let parsed: unknown;
  try {
    parsed = JSON.parse(readFileSync(file, "utf8")) as unknown;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return {
        allowedOrigins: [],
        auth: DEFAULT_REMOTE_AUTH_SETTINGS,
        sessionCookieName: DEFAULT_SESSION_COOKIE_NAME,
      };
    }
    throw new Error("Unable to read the unified remote configuration", { cause: error });
  }
  const record = asRecord(parsed);
  if (
    record === undefined ||
    record.Signature !== "codex-local-remote-v2/remote-settings/v1" ||
    record.Version !== 1
  ) {
    throw new Error("Invalid unified remote configuration format");
  }

  const authRecord = record.Auth === undefined ? {} : asRecord(record.Auth);
  if (authRecord === undefined) {
    throw new Error("Invalid Auth format in the unified remote configuration");
  }
  const allowedOrigins = readConfiguredOrigins(record.AllowedOrigins);
  const trustedProxyAddresses = readConfiguredAddresses(record.TrustedProxyAddresses);
  const trustedProxyNetworks = readConfiguredNetworks(record.TrustedProxyNetworks);
  const sessionCookieName = configuredSessionCookieName(record.SessionCookieName);
  const minimumPasswordLength = configuredInteger(
    authRecord.MinimumPasswordLength,
    DEFAULT_REMOTE_AUTH_SETTINGS.minimumPasswordLength,
    15,
    256,
    "Auth.MinimumPasswordLength",
  );
  const sessionIdleHours = configuredInteger(
    authRecord.SessionIdleHours,
    DEFAULT_REMOTE_AUTH_SETTINGS.sessionIdleTtlMs / (60 * 60 * 1_000),
    1,
    720,
    "Auth.SessionIdleHours",
  );
  const sessionAbsoluteDays = configuredInteger(
    authRecord.SessionAbsoluteDays,
    DEFAULT_REMOTE_AUTH_SETTINGS.sessionAbsoluteTtlMs / (24 * 60 * 60 * 1_000),
    1,
    365,
    "Auth.SessionAbsoluteDays",
  );
  const loginMaxAttempts = configuredInteger(
    authRecord.LoginMaxAttempts,
    DEFAULT_REMOTE_AUTH_SETTINGS.loginSourceMaxAttempts,
    1,
    1_000,
    "Auth.LoginMaxAttempts",
  );
  const globalLoginMaxAttempts = configuredInteger(
    authRecord.GlobalLoginMaxAttempts,
    DEFAULT_REMOTE_AUTH_SETTINGS.loginGlobalMaxAttempts,
    1,
    100_000,
    "Auth.GlobalLoginMaxAttempts",
  );
  const loginWindowMinutes = configuredInteger(
    authRecord.LoginWindowMinutes,
    DEFAULT_REMOTE_AUTH_SETTINGS.loginWindowMs / 60_000,
    1,
    1_440,
    "Auth.LoginWindowMinutes",
  );
  const loginLockoutMinutes = configuredInteger(
    authRecord.LoginLockoutMinutes,
    DEFAULT_REMOTE_AUTH_SETTINGS.loginLockoutMs / 60_000,
    1,
    10_080,
    "Auth.LoginLockoutMinutes",
  );
  if (globalLoginMaxAttempts < loginMaxAttempts) {
    throw new Error(
      "The unified remote configuration requires GlobalLoginMaxAttempts to be at least LoginMaxAttempts",
    );
  }
  const sidecarPort = configuredInteger(record.SidecarPort, 28_790, 1, 65_535, "SidecarPort");
  const brokerPort = configuredInteger(record.BrokerPort, 28_791, 1, 65_535, "BrokerPort");
  const upstreamPort = configuredInteger(record.UpstreamPort, 28_792, 1, 65_535, "UpstreamPort");
  if (new Set([sidecarPort, brokerPort, upstreamPort]).size !== 3) {
    throw new Error(
      "The unified remote configuration requires distinct Sidecar, Broker and app-server ports",
    );
  }

  return {
    allowedOrigins,
    auth: {
      minimumPasswordLength,
      sessionAbsoluteTtlMs: sessionAbsoluteDays * 24 * 60 * 60 * 1_000,
      sessionIdleTtlMs: sessionIdleHours * 60 * 60 * 1_000,
      loginSourceMaxAttempts: loginMaxAttempts,
      loginGlobalMaxAttempts: globalLoginMaxAttempts,
      loginWindowMs: loginWindowMinutes * 60_000,
      loginLockoutMs: loginLockoutMinutes * 60_000,
    },
    ...(record.DesktopSyncEnabled === undefined
      ? {}
      : { desktopSyncEnabled: configuredBoolean(record.DesktopSyncEnabled, "DesktopSyncEnabled") }),
    ...(record.SecurityMode === undefined
      ? {}
      : { securityMode: configuredString(record.SecurityMode, "SecurityMode") }),
    ...(record.BasePath === undefined
      ? {}
      : { basePath: configuredString(record.BasePath, "BasePath") }),
    ...(record.ListenMode === undefined
      ? {}
      : { listenMode: configuredString(record.ListenMode, "ListenMode") }),
    sessionCookieName,
    ...(record.BrokerPort === undefined ? {} : { brokerPort }),
    ...(record.SidecarPort === undefined ? {} : { sidecarPort }),
    ...(trustedProxyAddresses === undefined ? {} : { trustedProxyAddresses }),
    ...(trustedProxyNetworks === undefined ? {} : { trustedProxyNetworks }),
    ...(record.UpstreamPort === undefined ? {} : { upstreamPort }),
  };
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

function configuredString(value: unknown, label: string): string {
  if (typeof value !== "string" || value.trim() !== value || value.length === 0) {
    throw new Error(`Invalid ${label} in the unified remote configuration`);
  }
  return value;
}

function configuredSessionCookieName(value: unknown): string {
  const name = value === undefined ? DEFAULT_SESSION_COOKIE_NAME : value;
  if (typeof name !== "string" || !SESSION_COOKIE_NAME_PATTERN.test(name)) {
    throw new Error(
      "Invalid SessionCookieName in the unified remote configuration; use 1-64 ASCII letters, digits, underscores or hyphens, starting with a letter",
    );
  }
  return name;
}

function configuredBoolean(value: unknown, label: string): boolean {
  if (typeof value !== "boolean") {
    throw new Error(`Invalid ${label} in the unified remote configuration`);
  }
  return value;
}

function configuredInteger(
  value: unknown,
  fallback: number,
  minimum: number,
  maximum: number,
  label: string,
): number {
  if (value === undefined) return fallback;
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < minimum ||
    value > maximum
  ) {
    throw new Error(`Invalid ${label} in the unified remote configuration`);
  }
  return value;
}

function readConfiguredOrigins(value: unknown): readonly string[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 32) {
    throw new Error("Invalid AllowedOrigins in the unified remote configuration");
  }
  return [...new Set(value.map((candidate) => normalizeConfiguredOrigin(candidate)))];
}

function normalizeConfiguredOrigin(value: unknown): string {
  if (typeof value !== "string" || value.length > 512) {
    throw new Error("Invalid AllowedOrigins in the unified remote configuration");
  }
  try {
    const url = new URL(value);
    if (
      (url.protocol !== "http:" && url.protocol !== "https:") ||
      url.username ||
      url.password ||
      url.pathname !== "/" ||
      url.search ||
      url.hash
    ) {
      throw new Error("invalid origin");
    }
    return url.origin;
  } catch {
    throw new Error("Invalid AllowedOrigins in the unified remote configuration");
  }
}

function readConfiguredAddresses(value: unknown): readonly string[] | undefined {
  if (value === undefined) return undefined;
  if (!Array.isArray(value) || value.length > 32) {
    throw new Error("Invalid TrustedProxyAddresses in the unified remote configuration");
  }
  if (value.some((candidate) => typeof candidate !== "string" || isIP(candidate) === 0)) {
    throw new Error("Invalid TrustedProxyAddresses in the unified remote configuration");
  }
  return [
    ...new Set(value.map((candidate) => normalizeConfiguredProxyAddress(candidate as string))),
  ];
}

function readConfiguredNetworks(value: unknown): readonly string[] | undefined {
  if (value === undefined) return undefined;
  if (!Array.isArray(value) || value.length > 32) {
    throw new Error("Invalid TrustedProxyNetworks in the unified remote configuration");
  }
  const normalized = value.map((candidate) =>
    typeof candidate === "string" ? normalizeProxyNetwork(candidate) : undefined,
  );
  if (normalized.some((candidate) => candidate === undefined)) {
    throw new Error("Invalid TrustedProxyNetworks in the unified remote configuration");
  }
  return [...new Set(normalized as string[])];
}

function loadTrustedProxies(dataDir: string): {
  addresses: readonly string[];
  networks: readonly string[];
} {
  const file = path.win32.join(dataDir, "trusted-proxies.json");
  let parsed: unknown;
  try {
    parsed = JSON.parse(readFileSync(file, "utf8")) as unknown;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return { addresses: [], networks: [] };
    }
    throw new Error("Unable to read the trusted proxy configuration", { cause: error });
  }
  if (
    typeof parsed !== "object" ||
    parsed === null ||
    Array.isArray(parsed) ||
    Reflect.get(parsed, "Signature") !== "codex-local-remote-v2/trusted-proxies/v1" ||
    !Array.isArray(Reflect.get(parsed, "Addresses")) ||
    (Reflect.get(parsed, "Networks") !== undefined &&
      !Array.isArray(Reflect.get(parsed, "Networks")))
  ) {
    throw new Error("Invalid trusted proxy configuration format");
  }
  const addresses = Reflect.get(parsed, "Addresses") as unknown[];
  const networks = (Reflect.get(parsed, "Networks") ?? []) as unknown[];
  if (
    addresses.length > 32 ||
    networks.length > 32 ||
    addresses.some((address) => typeof address !== "string" || isIP(address) === 0) ||
    networks.some((network) => typeof network !== "string" || !normalizeProxyNetwork(network))
  ) {
    throw new Error(
      "The trusted proxy configuration may contain only valid IP addresses or CIDR networks",
    );
  }
  return {
    addresses: [
      ...new Set(addresses.map((address) => normalizeConfiguredProxyAddress(address as string))),
    ],
    networks: [
      ...new Set(networks.map((network) => normalizeProxyNetwork(network as string) as string)),
    ],
  };
}

function normalizeConfiguredProxyAddress(address: string): string {
  const normalized = address.toLocaleLowerCase("en-US").split("%", 1)[0] ?? "";
  return normalized.startsWith("::ffff:") ? normalized.slice("::ffff:".length) : normalized;
}

function normalizeProxyNetwork(value: string): string | undefined {
  const separator = value.lastIndexOf("/");
  if (separator <= 0 || separator === value.length - 1) return undefined;
  const address = normalizeConfiguredProxyAddress(value.slice(0, separator));
  const version = isIP(address);
  const prefix = Number(value.slice(separator + 1));
  const maximum = version === 4 ? 32 : version === 6 ? 128 : -1;
  if (!Number.isInteger(prefix) || prefix < 0 || prefix > maximum) return undefined;
  return `${address}/${prefix}`;
}

export function parseCliInvocation(args: string[]): CliInvocation {
  const [command, ...rest] = args;
  if (
    command === undefined ||
    ((command === "--help" || command === "-h" || command === "help") && rest.length === 0)
  ) {
    return { command: "help" };
  }
  if (command !== "serve" && command !== "setup-password" && command !== "register-project") {
    throw new Error("Use serve, setup-password or register-project");
  }
  const values = parseFlags(rest);

  if (command === "serve") {
    assertAllowedFlags(values, [
      "app-server-url",
      "base-path",
      "codex-path",
      "data-dir",
      "host",
      "maintenance-token-file",
      "no-desktop-sync",
      "port",
      "security-mode",
      "web-dir",
    ]);
    return {
      command,
      config: compactConfig({
        appServerUrl: normalizeOptionalAppServerUrl(values.get("app-server-url")),
        basePath: values.get("base-path"),
        codexPath: values.get("codex-path"),
        dataDir: values.get("data-dir"),
        desktopSyncEnabled: values.has("no-desktop-sync") ? false : undefined,
        host: values.get("host"),
        maintenanceTokenFile: values.get("maintenance-token-file"),
        port: parsePort(values.get("port")),
        securityMode: values.get("security-mode"),
        webDir: values.get("web-dir"),
      }),
    };
  }

  if (command === "setup-password") {
    assertAllowedFlags(values, ["data-dir"]);
    const dataDir = values.get("data-dir");
    return {
      command,
      config: dataDir === undefined ? {} : { dataDir },
    };
  }

  assertAllowedFlags(values, ["data-dir", "id", "name", "root"]);
  const id = values.get("id");
  const name = values.get("name");
  const root = values.get("root");
  if (!id || !name || !root) {
    throw new Error("register-project requires --id, --name and --root");
  }
  const dataDir = values.get("data-dir");
  return {
    command,
    config: dataDir === undefined ? {} : { dataDir },
    project: { id, name, root },
  };
}

function normalizeBasePath(value: string): string {
  const withoutTrailing = value.length > 1 ? value.replace(/\/+$/u, "") : value;
  if (
    withoutTrailing === "/" ||
    !withoutTrailing.startsWith("/") ||
    withoutTrailing.includes("//") ||
    withoutTrailing.split("/").some((segment, index) => {
      if (index === 0) {
        return false;
      }
      return (
        segment.length === 0 ||
        segment === "." ||
        segment === ".." ||
        !/^[A-Za-z0-9._~-]+$/u.test(segment)
      );
    })
  ) {
    throw new Error("Invalid Sidecar base path");
  }
  return withoutTrailing;
}

function normalizeListenHost(value: string): "0.0.0.0" | "127.0.0.1" | "::1" {
  switch (value.trim().toLocaleLowerCase("en-US")) {
    case "lan":
    case "0.0.0.0":
      return "0.0.0.0";
    case "localhost":
    case "127.0.0.1":
      return "127.0.0.1";
    case "::1":
      return "::1";
    default:
      throw new Error("Invalid Sidecar listen mode; use localhost or lan");
  }
}

function parsePort(value: string | undefined): number | undefined {
  if (value === undefined || value.length === 0) {
    return undefined;
  }
  if (!/^\d+$/u.test(value)) {
    throw new Error("Invalid Sidecar port");
  }
  return Number(value);
}

function parseBooleanSwitch(value: string | undefined): boolean | undefined {
  if (value === undefined) {
    return undefined;
  }
  switch (value.trim().toLocaleLowerCase("en-US")) {
    case "1":
    case "on":
    case "true":
    case "yes":
      return true;
    case "0":
    case "false":
    case "no":
    case "off":
      return false;
    default:
      throw new Error("Invalid Sidecar Desktop sync flag");
  }
}

function normalizeLocalMaintenanceTokenFile(value: string | undefined): string | undefined {
  if (value === undefined || value.length === 0) {
    return undefined;
  }
  if (!path.win32.isAbsolute(value)) {
    throw new Error("The Sidecar maintenance token must use an absolute path");
  }
  const resolved = path.win32.normalize(value);
  if (resolved.startsWith("\\\\")) {
    throw new Error("The Sidecar maintenance token must use a local file path");
  }
  return resolved;
}

function parseFlags(args: string[]): Map<string, string> {
  const result = new Map<string, string>();
  for (let index = 0; index < args.length; ) {
    const flag = args[index];
    if (!flag?.startsWith("--")) {
      throw new Error("Unsupported argument or missing argument value");
    }
    const key = flag.slice(2);
    if (result.has(key)) {
      throw new Error("Duplicate arguments are not supported");
    }
    if (key === "no-desktop-sync") {
      result.set(key, "");
      index += 1;
      continue;
    }
    const value = args[index + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new Error("Unsupported argument or missing argument value");
    }
    result.set(key, value);
    index += 2;
  }
  return result;
}

function assertAllowedFlags(values: Map<string, string>, allowed: string[]): void {
  const allowlist = new Set(allowed);
  if ([...values.keys()].some((key) => !allowlist.has(key))) {
    throw new Error("Unsupported argument");
  }
}

function compactConfig(input: {
  appServerUrl?: string | undefined;
  host?: string | undefined;
  port?: number | undefined;
  basePath?: string | undefined;
  codexPath?: string | undefined;
  dataDir?: string | undefined;
  desktopSyncEnabled?: boolean | undefined;
  maintenanceTokenFile?: string | undefined;
  securityMode?: string | undefined;
  webDir?: string | undefined;
}): SidecarConfigOverrides {
  return {
    ...(input.appServerUrl === undefined ? {} : { appServerUrl: input.appServerUrl }),
    ...(input.host === undefined ? {} : { host: input.host }),
    ...(input.port === undefined ? {} : { port: input.port }),
    ...(input.basePath === undefined ? {} : { basePath: input.basePath }),
    ...(input.codexPath === undefined ? {} : { codexPath: input.codexPath }),
    ...(input.dataDir === undefined ? {} : { dataDir: input.dataDir }),
    ...(input.desktopSyncEnabled === undefined
      ? {}
      : { desktopSyncEnabled: input.desktopSyncEnabled }),
    ...(input.maintenanceTokenFile === undefined
      ? {}
      : { maintenanceTokenFile: input.maintenanceTokenFile }),
    ...(input.securityMode === undefined ? {} : { securityMode: input.securityMode }),
    ...(input.webDir === undefined ? {} : { webDir: input.webDir }),
  };
}

function normalizeSecurityMode(value: string): SidecarSecurityMode {
  switch (value.trim().toLocaleLowerCase("en-US")) {
    case "https":
      return "https";
    case "insecure-http":
      return "insecure-http";
    default:
      throw new Error("Invalid Sidecar security mode; use https or insecure-http");
  }
}

function normalizeOptionalAppServerUrl(value: string | undefined): string | undefined {
  return value === undefined ? undefined : normalizeLoopbackWebSocketEndpoint(value);
}
