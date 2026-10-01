import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { parseCliInvocation, resolveSidecarConfig } from "./config.js";

describe("resolveSidecarConfig", () => {
  it("uses the installation defaults agreed for the Windows sidecar", () => {
    expect(
      resolveSidecarConfig({
        environment: {
          LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local",
        },
      }),
    ).toMatchObject({
      appServerUrl: "ws://127.0.0.1:28791/",
      basePath: "/codex-remote",
      dataDir: path.win32.join("C:\\Users\\fixture\\AppData\\Local", "CodexLocalRemoteV2"),
      desktopSyncEnabled: true,
      host: "0.0.0.0",
      port: 28_790,
      securityMode: "https",
      sessionCookieName: "codex_remote_session",
    });
  });

  it("requires an explicit insecure HTTP transport mode", () => {
    expect(
      resolveSidecarConfig({
        environment: {
          CODEX_REMOTE_V2_SECURITY_MODE: "insecure-http",
          LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local",
        },
      }),
    ).toMatchObject({ securityMode: "insecure-http" });

    expect(() =>
      resolveSidecarConfig({
        environment: {
          CODEX_REMOTE_V2_SECURITY_MODE: "off",
          LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local",
        },
      }),
    ).toThrow("https or insecure-http");
  });

  it("lets CLI listener flags override non-secret environment configuration", () => {
    expect(
      resolveSidecarConfig({
        cli: {
          appServerUrl: "ws://127.0.0.1:19002/shared",
          basePath: "/phone/",
          dataDir: "D:\\Remote State",
          host: "::1",
          port: 19_001,
          securityMode: "insecure-http",
        },
        environment: {
          CODEX_REMOTE_V2_BASE_PATH: "/from-env",
          CODEX_REMOTE_V2_PORT: "29999",
          LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local",
        },
      }),
    ).toMatchObject({
      appServerUrl: "ws://127.0.0.1:19002/shared",
      basePath: "/phone",
      dataDir: "D:\\Remote State",
      host: "::1",
      port: 19_001,
      securityMode: "insecure-http",
    });
  });

  it("supports LAN and localhost listener selections while rejecting arbitrary addresses", () => {
    expect(
      resolveSidecarConfig({
        cli: { host: "lan" },
        environment: { LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local" },
      }),
    ).toMatchObject({ host: "0.0.0.0" });

    expect(
      resolveSidecarConfig({
        environment: {
          CODEX_REMOTE_V2_HOST: "localhost",
          LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local",
        },
      }),
    ).toMatchObject({ host: "127.0.0.1" });

    expect(() =>
      resolveSidecarConfig({
        environment: {
          CODEX_REMOTE_V2_BASE_PATH: "/../escape",
          LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local",
        },
      }),
    ).toThrow("base path");

    expect(() =>
      resolveSidecarConfig({
        cli: { host: "192.0.2.32" },
        environment: { LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local" },
      }),
    ).toThrow("localhost or lan");

    expect(() =>
      resolveSidecarConfig({
        environment: {
          CODEX_REMOTE_V2_APP_SERVER_WS_URL: "ws://0.0.0.0:28791",
          LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local",
        },
      }),
    ).toThrow("loopback");
  });

  it("allows an explicit environment opt-out from Desktop thread synchronization", () => {
    expect(
      resolveSidecarConfig({
        environment: {
          CODEX_REMOTE_V2_DESKTOP_SYNC: "false",
          LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local",
        },
      }),
    ).toMatchObject({ desktopSyncEnabled: false });

    expect(() =>
      resolveSidecarConfig({
        environment: {
          CODEX_REMOTE_V2_DESKTOP_SYNC: "sometimes",
          LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local",
        },
      }),
    ).toThrow("Desktop sync flag");
  });

  it("loads exact trusted proxy IP addresses and CIDR networks from the private DataDir", () => {
    const dataDir = mkdtempSync(path.join(os.tmpdir(), "codex-remote-proxies-"));
    try {
      writeFileSync(
        path.join(dataDir, "trusted-proxies.json"),
        JSON.stringify({
          Signature: "codex-local-remote-v2/trusted-proxies/v1",
          Addresses: ["192.0.2.64", "2001:db8::64", "192.0.2.64"],
          Networks: ["192.0.2.0/24", "2001:db8::/64", "192.0.2.0/24"],
        }),
        "utf8",
      );

      expect(
        resolveSidecarConfig({
          cli: { dataDir },
          environment: { LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local" },
        }).trustedProxyAddresses,
      ).toEqual(["192.0.2.64", "2001:db8::64"]);
      expect(
        resolveSidecarConfig({
          cli: { dataDir },
          environment: { LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local" },
        }).trustedProxyNetworks,
      ).toEqual(["192.0.2.0/24", "2001:db8::/64"]);
    } finally {
      rmSync(dataDir, { force: true, recursive: true });
    }
  });

  it("loads the unified remote-settings file and derives the Broker endpoint", () => {
    const dataDir = mkdtempSync(path.join(os.tmpdir(), "codex-remote-settings-"));
    try {
      writeFileSync(
        path.join(dataDir, "remote-settings.json"),
        JSON.stringify({
          Signature: "codex-local-remote-v2/remote-settings/v1",
          Version: 1,
          ListenMode: "localhost",
          SecurityMode: "insecure-http",
          SidecarPort: 29_000,
          BrokerPort: 29_001,
          UpstreamPort: 29_002,
          BasePath: "/remote",
          SessionCookieName: "codex_remote_session_remote",
          DesktopSyncEnabled: false,
          AllowedOrigins: ["HTTPS://remote.example.test:443"],
          TrustedProxyAddresses: ["192.0.2.64"],
          TrustedProxyNetworks: ["192.0.2.0/24"],
          Auth: {
            MinimumPasswordLength: 18,
            SessionIdleHours: 12,
            SessionAbsoluteDays: 30,
            LoginMaxAttempts: 7,
            GlobalLoginMaxAttempts: 70,
            LoginWindowMinutes: 20,
            LoginLockoutMinutes: 30,
          },
        }),
        "utf8",
      );

      expect(
        resolveSidecarConfig({
          cli: { dataDir },
          environment: { LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local" },
        }),
      ).toMatchObject({
        appServerUrl: "ws://127.0.0.1:29001/",
        basePath: "/remote",
        desktopSyncEnabled: false,
        host: "127.0.0.1",
        port: 29_000,
        securityMode: "insecure-http",
        sessionCookieName: "codex_remote_session_remote",
        allowedOrigins: ["https://remote.example.test"],
        trustedProxyAddresses: ["192.0.2.64"],
        trustedProxyNetworks: ["192.0.2.0/24"],
        auth: {
          minimumPasswordLength: 18,
          sessionAbsoluteTtlMs: 30 * 24 * 60 * 60 * 1_000,
          sessionIdleTtlMs: 12 * 60 * 60 * 1_000,
          loginSourceMaxAttempts: 7,
          loginGlobalMaxAttempts: 70,
          loginWindowMs: 20 * 60_000,
          loginLockoutMs: 30 * 60_000,
        },
      });

      expect(
        resolveSidecarConfig({
          cli: { dataDir },
          environment: {
            CODEX_REMOTE_V2_APP_SERVER_WS_URL: "ws://127.0.0.1:29001/ws/private-runtime-capability",
            LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local",
          },
        }).appServerUrl,
      ).toBe("ws://127.0.0.1:29001/ws/private-runtime-capability");
    } finally {
      rmSync(dataDir, { force: true, recursive: true });
    }
  });

  it("rejects duplicate unified listener ports", () => {
    const dataDir = mkdtempSync(path.join(os.tmpdir(), "codex-remote-settings-invalid-"));
    try {
      writeFileSync(
        path.join(dataDir, "remote-settings.json"),
        JSON.stringify({
          Signature: "codex-local-remote-v2/remote-settings/v1",
          Version: 1,
          SidecarPort: 29_000,
          BrokerPort: 29_000,
          UpstreamPort: 29_002,
        }),
        "utf8",
      );

      expect(() =>
        resolveSidecarConfig({
          cli: { dataDir },
          environment: { LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local" },
        }),
      ).toThrow("distinct Sidecar, Broker and app-server ports");
    } finally {
      rmSync(dataDir, { force: true, recursive: true });
    }
  });

  it("rejects unsafe unified session cookie names", () => {
    const dataDir = mkdtempSync(path.join(os.tmpdir(), "codex-remote-cookie-name-"));
    try {
      writeFileSync(
        path.join(dataDir, "remote-settings.json"),
        JSON.stringify({
          Signature: "codex-local-remote-v2/remote-settings/v1",
          Version: 1,
          SessionCookieName: "codex remote session",
        }),
        "utf8",
      );

      expect(() =>
        resolveSidecarConfig({
          cli: { dataDir },
          environment: { LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local" },
        }),
      ).toThrow("SessionCookieName");
    } finally {
      rmSync(dataDir, { force: true, recursive: true });
    }
  });
});

describe("parseCliInvocation", () => {
  it("provides a secret-free help entrypoint", () => {
    expect(parseCliInvocation(["--help"])).toEqual({ command: "help" });
  });

  it("supports serve listener flags without accepting password material", () => {
    expect(
      parseCliInvocation([
        "serve",
        "--app-server-url",
        "ws://127.0.0.1:18791",
        "--host",
        "lan",
        "--port",
        "18790",
        "--base-path",
        "/codex-remote",
        "--codex-path",
        "C:\\Codex\\codex.exe",
        "--data-dir",
        "D:\\Remote State",
        "--maintenance-token-file",
        "D:\\Remote State\\maintenance.token",
        "--security-mode",
        "insecure-http",
      ]),
    ).toEqual({
      command: "serve",
      config: {
        appServerUrl: "ws://127.0.0.1:18791/",
        basePath: "/codex-remote",
        codexPath: "C:\\Codex\\codex.exe",
        dataDir: "D:\\Remote State",
        host: "lan",
        maintenanceTokenFile: "D:\\Remote State\\maintenance.token",
        port: 18_790,
        securityMode: "insecure-http",
      },
    });

    expect(() => parseCliInvocation(["setup-password", "--password", "secret"])).toThrow(
      "Unsupported argument",
    );
  });

  it("accepts only a local maintenance capability file path", () => {
    expect(
      resolveSidecarConfig({
        cli: { maintenanceTokenFile: "D:\\Remote State\\maintenance.token" },
        environment: { LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local" },
      }),
    ).toMatchObject({ maintenanceTokenFile: "D:\\Remote State\\maintenance.token" });

    expect(() =>
      resolveSidecarConfig({
        cli: { maintenanceTokenFile: "\\\\server\\share\\maintenance.token" },
        environment: { LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local" },
      }),
    ).toThrow("local file path");

    expect(() =>
      resolveSidecarConfig({
        cli: { maintenanceTokenFile: "maintenance.token" },
        environment: { LOCALAPPDATA: "C:\\Users\\fixture\\AppData\\Local" },
      }),
    ).toThrow("absolute path");
  });

  it("supports an explicit serve-only Desktop synchronization opt-out", () => {
    expect(
      parseCliInvocation(["serve", "--host", "localhost", "--no-desktop-sync", "--port", "18790"]),
    ).toEqual({
      command: "serve",
      config: {
        desktopSyncEnabled: false,
        host: "localhost",
        port: 18_790,
      },
    });

    expect(() => parseCliInvocation(["setup-password", "--no-desktop-sync"])).toThrow(
      "Unsupported argument",
    );
  });
});
