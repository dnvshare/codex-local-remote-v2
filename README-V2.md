# Codex Local Remote V2

V2 keeps the existing Broker, Sidecar, Web UI, authentication, file features,
and app-server protocol integration. It replaces the Windows hot-handoff state
machine with one explicit cold-start lifecycle.

## Client recommendation

The Web PWA is currently the best overall experience. The Android, iPhone/iPad,
Mac Catalyst and Windows clients are thin shells around the same Web UI and are
useful when a native app container is preferred, but they do not replace the
browser/PWA path or the Windows V2 host.

## Fixed startup model

```text
explicit Open
  -> validate configuration, ports, Desktop runtime, and single-owner state
  -> optionally close one native Desktop root after explicit authorization
  -> start Infrastructure Host in a kill-on-close Windows Job
       -> Broker on 127.0.0.1:28791
       -> owned app-server on 127.0.0.1:28792
       -> Sidecar on 0.0.0.0:28790 by default
  -> launch Desktop from the same-session Explorer primary token
  -> Desktop and Sidecar attach to the same Broker
  -> publish ready only after the shared-owner proof passes
```

There is no hot attach. If native Desktop is already open, `Open` first returns
`restart-authorization-required`. Only an explicit
`Open -AllowDesktopRestart` may close and reopen Desktop once.

## Build and register without starting

Run from an Administrator CMD or PowerShell window:

```cmd
scripts\windows-v2\Register-CodexLocalRemoteV2.cmd -NoStart
```

Defaults:

- DataDir: `%LOCALAPPDATA%\CodexLocalRemoteV2`
- task: `Codex Local Remote V2`
- Sidecar: LAN, port `28790`, path `/codex-remote`
- Broker: loopback port `28791`
- owned app-server: loopback port `28792`
- security: `https`

Registration deploys one content-addressed release and creates an on-demand,
trigger-free `Interactive` / `Highest` task. It does not start Remote or close
Desktop. Repeated deployment reuses an identical release instead of copying it
again.

The first registration creates the unified settings file. To use insecure HTTP
for a trusted LAN diagnosis, edit `remote-settings.json` and set
`"SecurityMode": "insecure-http"`, then use the launcher menu option 1.

For a one-time HTTPS registration override, use:

```cmd
scripts\windows-v2\Register-CodexLocalRemoteV2.cmd -NoStart -SecurityMode https
```

For local-only Sidecar use:

```cmd
scripts\windows-v2\Register-CodexLocalRemoteV2.cmd -NoStart -ListenMode localhost
```

The command-line overrides apply only to that registration and do not rewrite
`remote-settings.json`. Edit the unified settings file when the value should be
used by later menu starts.

## Password and project

These commands do not start or restart Desktop:

```cmd
scripts\windows-v2\Setup-CodexLocalRemoteV2Password.cmd
scripts\windows-v2\Register-CodexLocalRemoteV2Project.cmd -Id main -Name "codex-local-remote" -Root "C:\Projects\codex-local-remote"
```

The password is read interactively and is never accepted through a command-line
argument or environment variable.

## Unified remote settings

V2 reads its unified configuration from:

```text
%LOCALAPPDATA%\CodexLocalRemoteV2\remote-settings.json
```

`Register-CodexLocalRemoteV2.ps1` creates this file on the first registration.
The repository includes [remote-settings.example.json](remote-settings.example.json)
as a copyable template. It contains no password, token, host name, or private
network.

The main options are:

| Field                                            | Meaning                                                                                                                                                                                  |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ListenMode`                                     | `lan` listens on the LAN-capable address; `localhost` listens only on this PC.                                                                                                           |
| `SecurityMode`                                   | `https` requires HTTPS for login; `insecure-http` permits HTTP cookies but does not disable password, same-origin, CSRF, throttling, or idempotency checks.                              |
| `SidecarPort`                                    | Browser/Web and Sidecar port.                                                                                                                                                            |
| `BrokerPort`                                     | Loopback-only Broker port.                                                                                                                                                               |
| `UpstreamPort`                                   | Loopback-only owned app-server port.                                                                                                                                                     |
| `BasePath`                                       | URL path prefix, normally `/codex-remote`.                                                                                                                                               |
| `SessionCookieName`                              | This instance's authentication Cookie name. Use a different safe ASCII name for every instance sharing one browser domain and path; the default preserves single-instance compatibility. |
| `DesktopSyncEnabled`                             | Whether newly created managed threads are announced to Desktop.                                                                                                                          |
| `AllowedOrigins`                                 | Optional exact browser origins such as `https://remote.example.test:2342`; an empty list keeps the normal same-origin check. Do not add a path, query, wildcard, username, or password.  |
| `TrustedProxyAddresses` / `TrustedProxyNetworks` | Exact proxy IPs or CIDR networks allowed to supply forwarded host/protocol headers.                                                                                                      |
| `Auth`                                           | Password minimum length, session lifetime, and login throttling limits.                                                                                                                  |

When two instances are opened in the same browser under one domain and path,
give them different Cookie names, for example:

```json
{
  "SessionCookieName": "codex_remote_session_primary"
}
```

Use this value in the second instance instead:

```json
{
  "SessionCookieName": "codex_remote_session_surface"
}
```

The name is an instance label, not a password. It must contain only ASCII
letters, digits, `_`, or `-`, start with a letter, and be at most 64 characters.

All three ports must be different. The default file is intentionally safe for
the existing shared-owner layout: Broker and app-server remain loopback-only,
while only Sidecar can listen on the LAN.

After editing the file:

- `HotApply` reloads authentication, the session Cookie name, allowed origins,
  trusted proxies, and Desktop synchronization. It restarts only Sidecar; it
  does not restart Broker, app-server, or Codex Desktop.
- A change to `ListenMode`, any port, `BasePath`, or `SecurityMode` requires a
  full V2 start so the generated owner configuration and all readiness probes
  agree. The launcher will report this instead of silently using an old value.

The launcher menu option 1 uses `remote-settings.json`. Option 2 temporarily
overrides only `SecurityMode` to `insecure-http`; all other values still come
from the file. Option 2 is for a trusted local/LAN HTTP diagnosis and must not
be used as a public HTTPS replacement. Explicit command-line parameters remain
available for one registration, but they do not rewrite the unified settings
file.

## Explicit control

For this Windows installation, the source root also contains a one-click V2
launcher. It runs in an independent, self-deleting scheduled task so closing
Desktop cannot terminate the handoff:

```cmd
Start-CodexLocalRemoteV2-OneClick.cmd
```

With no arguments, the launcher displays a small menu. Choose option 1 for a
V2-only start using the values in `remote-settings.json`: it registers the
current V2 release, cleans only receipt-proven orphaned V2 infrastructure, rejects any
unowned process that can affect V2 ownership or managed ports unless you
explicitly confirm the listed unknown port owner, and opens V2 with one
authorized Desktop restart. It does not use the V1 dispatcher, DataDir, task,
or ports, although the authorized cold handoff may close the currently running
native Desktop once. This option does not ask for an additional script
confirmation. Progress is written to
`%LOCALAPPDATA%\CodexLocalRemoteV2\switch.log` without passwords or capability
tokens.

The interactive menu is:

1. Forced V2 restart using `remote-settings.json`;
2. Forced V2 restart with temporary `insecure-http`;
3. Hot-apply Web/Sidecar without restarting Desktop;
4. Prepare and register a release without starting or closing Desktop;
5. Show V2 status;
6. Close managed V2 and restore native Desktop;
7. Close managed V2 without restarting Codex Desktop;
8. Show the last 80 lines of the switch log;

- `0`. Exit the menu.

Startup blockers are handled by ownership, not by a V1/V2 product label:

- a receipt-proven orphaned V2 Broker, app-server, or Sidecar is stopped;
- one native Desktop root is closed only with explicit restart authorization;
- an unowned app-server, an occupied V2 managed port, or multiple Desktop roots
  fails closed with a specific diagnostic and is never terminated speculatively;
- unrelated processes and listeners on ports outside the V2 configuration are
  ignored.

The same launcher accepts independent actions and deployment options:

```cmd
Start-CodexLocalRemoteV2-OneClick.cmd -Action Prepare
Start-CodexLocalRemoteV2-OneClick.cmd -Action Open
Start-CodexLocalRemoteV2-OneClick.cmd -Action Status
Start-CodexLocalRemoteV2-OneClick.cmd -Action Close
Start-CodexLocalRemoteV2-OneClick.cmd -Action Start -ProjectRoot "D:\Projects\my-project"
Start-CodexLocalRemoteV2-OneClick.cmd -Action Prepare -ListenMode localhost -SecurityMode https
```

`Start-CodexLocalRemoteV2-OneClick.cmd` opens the Chinese menu. Use
`Start-CodexLocalRemoteV2-OneClick-EN.cmd` for the equivalent English menu; both
menus keep the same actions and return to the menu after each operation.

The Web UI defaults to Simplified Chinese and provides an `EN / 中` switch. The
independent mobile setup shell uses the same `codex-local-remote:locale` browser
setting and also provides a language switch. Backend, Broker, Sidecar, app-server,
diagnostic, and Windows service messages use English canonical text; task content
and model output are preserved as received.

`Prepare` registers the current build and never starts or closes Desktop.
`Open` starts the already registered V2; it may restart native Desktop once unless
`-NoDesktopRestart` is supplied. `Status` only reports the V2 dispatcher
state. `Close` closes managed V2 and restores native Desktop; the menu's option 7
closes managed V2 without restoring native Desktop, and option 8 only displays the
recent switch log.
`-SkipProjectRegistration` leaves projects unchanged. Without an explicit
`-ProjectRoot`, existing V2 project registrations are preserved and no project
is inferred from another installation.
`-ListenMode localhost` binds Sidecar to loopback; the default `lan` binds it
to the LAN-capable address. `-SecurityMode https` is for an HTTPS reverse
proxy. These command-line values are one-registration overrides; the unified
file remains the default source for later menu starts.

```cmd
scripts\windows-v2\CodexLocalRemoteV2.Control.cmd -Operation Status
scripts\windows-v2\CodexLocalRemoteV2.Control.cmd -Operation Open
scripts\windows-v2\CodexLocalRemoteV2.Control.cmd -Operation Open -AllowDesktopRestart
scripts\windows-v2\CodexLocalRemoteV2.Control.cmd -Operation Close
```

`Close` stops the managed Desktop and infrastructure, then starts native
Desktop without `CODEX_APP_SERVER_WS_URL`. Closing Desktop yourself stops the
Remote infrastructure and leaves Desktop closed.

Do not run `Open` or `Close` from the Codex Desktop task doing the development;
the user should run the CMD command from a separate terminal when ready for the
real handoff test.

## Network boundary

Only Sidecar may listen on LAN. Never port-forward `28791` or `28792`. For
`insecure-http`, forward the desired router port to this PC's TCP `28790` and
open:

```text
http://PUBLIC_HOST:PUBLIC_PORT/codex-remote/
```

For `https` mode, the public URL must be HTTPS-terminated by IIS, Caddy, Nginx,
or another trusted reverse proxy. The proxy forwards only to Sidecar's HTTP
listener and must preserve the configured BasePath and forwarded host/protocol.

`insecure-http` permits a non-Secure session cookie but keeps password,
same-origin, CSRF, throttling, and mutation idempotency checks enabled. Prefer
`https` for persistent public exposure.

This repository contains only the V2 control path; the legacy V1 control directory
is intentionally not included.
