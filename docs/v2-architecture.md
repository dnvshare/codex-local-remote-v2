# V2 Windows architecture

## Goals

V2 removes the requirement to prove a hot switch between a native private
stdio app-server and a managed WebSocket app-server. It accepts one explicit
Desktop restart when Remote is enabled and makes the shared owner relationship
true from process creation onward.

## Kept from V1

- Broker protocol and subscription barriers;
- Sidecar product API, password sessions, CSRF, throttling and idempotency;
- Web and mobile UI;
- registered projects, files, attachments, history and approvals;
- loopback-only raw app-server and Broker boundary.

## Replaced from V1

- selected/active/running generation handoff state machine;
- attempted hot attachment to an existing Desktop;
- lease, intent and receipt compensation across multiple controllers;
- sealing or source selection inside `Open`;
- persistent or machine-wide `CODEX_APP_SERVER_WS_URL` changes.

## Ownership and processes

The on-demand scheduled task is the only coordinator. It has no triggers,
missed-start behavior, or restart policy. The coordinator creates an
Infrastructure Host and assigns that host to a kill-on-close Windows Job before
releasing its startup gate. Broker, Sidecar, and the Broker-owned app-server are
therefore descendants of the assigned host and cannot survive coordinator
cleanup as orphan listeners.

Desktop is not assigned to the infrastructure Job. It is created from the
same-user, same-session Explorer primary token. Its environment is copied from
the coordinator with any inherited `CODEX_APP_SERVER_WS_URL` removed, then the
managed endpoint is added only for a Remote launch. Native restoration launches
with that variable absent.

## State layout

```text
%LOCALAPPDATA%\CodexLocalRemoteV2\
  config.json                 registration settings
  remote-settings.json        editable listen, security, proxy and auth settings
  current-release.json        validated content-addressed pointer
  coordinator-state.json      lifecycle status only
  state.json                  Sidecar password, sessions and projects
  broker-capability.token     local Broker capability, never printed
  control\                    stable dispatcher and task entry
  Releases\<sha256>\          immutable runtime payload
  logs\                       process diagnostics without secrets
```

The separation between `coordinator-state.json` and Sidecar `state.json` is a
hard contract.

The lifecycle entry points have separate boundaries:

- `Prepare` / `Register -NoStart` deploy and register an immutable release only;
- menu `Start` performs the forced V2 shutdown, registration and one authorized
  Desktop cold handoff;
- `Open` uses the already registered release and can return immediately when the
  same owner is already ready, but requires `-AllowDesktopRestart` for a native
  Desktop that is already running;
- `HotApply` can switch only Web and Sidecar payloads after the compatibility gate;
- `Close` stops the managed owner and restores native Desktop; `Status` is read-only.

## Failure behavior

- preflight failure: do not close Desktop;
- startup failure after Desktop handoff: stop the infrastructure Job, close the
  managed Desktop if present, and restore native Desktop;
- Broker or Sidecar failure while ready: close managed Desktop, stop the Job,
  and restore native Desktop;
- explicit Close: close managed Desktop, stop the Job, restore native Desktop;
- user closes Desktop: stop the Job and do not reopen Desktop;
- Windows restart, login, update or sleep recovery: no task trigger runs, so
  normal vendor Desktop behavior remains native.

## Security modes

`https` emits Secure session cookies. `insecure-http` omits only the Secure
cookie attribute so a direct HTTP LAN or router-forwarded endpoint can work.
Both modes retain authentication, login throttling, same-origin enforcement,
CSRF validation and mutation idempotency.

Broker and app-server are always loopback-only and must never be forwarded or
published. Sidecar defaults to LAN and can be switched to localhost at
registration.
