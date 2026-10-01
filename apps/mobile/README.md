# Codex Local Remote Mobile

This directory contains thin native client shells around the existing Sidecar
Web UI. Android, iPhone, and Mac Catalyst reuse the Capacitor 6.2 shell. Windows
uses a small WPF/WebView2 host. None of these clients duplicate the product UI:
after the local connection page selects a Sidecar URL, that URL becomes the main
WebView document so the existing same-origin session cookie, CSRF, SSE, upload,
and download paths remain unchanged.

## Recommended experience

The Web version installed as a PWA currently provides the best overall experience.
The native clients are optional shells around that same Web UI; use them when a
standalone app container or platform permission bridge is more convenient. The
Windows V2 host and Codex Desktop still run on Windows;
the iPhone/iPad, Android, Mac Catalyst and Windows packages are clients only.

## Configure on the device

The first launch shows a connection form. The Sidecar URL is stored only in the
app WebView's local storage and is applied immediately. A native-only entry on
the login, connection-error, and settings screens returns to the same form for
later changes. Use HTTPS for normal device use. HTTP is accepted only for
localhost and private LAN addresses. The setup shell follows the device
language on first launch, then remembers the shared `codex-local-remote:locale`
choice. Use its `EN / 中` button to switch between Simplified Chinese and
English; native Android diagnostic dialogs follow the same system locale. When a
saved address is present, the shell briefly attempts automatic connection; use
the stop control on the connection page to cancel that attempt and enter another
address instead.

## Platform boundary

- `android/` is the Android Capacitor shell.
- `ios/` is the shared iPhone/iPad shell and is also enabled for Mac Catalyst.
- `windows/` is the Windows x64 WPF/WebView2 shell.
- `src/` is the device-local connection settings and startup page.
- The product UI remains `apps/web`, served by Sidecar without mobile-specific
  branches.
- macOS currently means the client shell only. Running the Codex/V2 host stack
  on macOS is not implemented.
- Native signing, provisioning, App Store metadata, Microsoft packaging, and
  remote Mac builds are intentionally not configured here.

After `sync`, open the generated platform project with Android Studio or Xcode.
The Android project targets Java 17 and can be built with the documented local
JDK 18. The iOS 13+ project uses CocoaPods; open `ios/App/App.xcworkspace` after
running `pod install` on a Mac. In Xcode, the same target can be selected for
Mac Catalyst to produce the macOS client shell.

For Windows x64, run `build_windows_x64.cmd` from Explorer or a terminal. The
script builds the shared local connection page first, then publishes only the
Windows client. The Windows shell stores WebView2 state below the current user's
local application data so the selected Sidecar address and authenticated Web
session can persist between launches. The existing Web settings entry can send
the Windows shell back to its local connection page through a small WebView2
message bridge.

## GitHub Actions iOS build

The repository includes a manual workflow at
`.github/workflows/build-ios-unsigned-ipa.yml`. Open the repository's
**Actions** tab, select **Build unsigned iOS IPA**, choose **Run workflow**, and
download the `codex-local-remote-ios-unsigned` artifact from the completed run.
The workflow runs only when manually triggered. It uses a GitHub-hosted macOS
15 runner, regenerates the Capacitor shell, installs CocoaPods dependencies,
archives the iOS target with code signing disabled, and packages the resulting
app as an IPA.

The IPA is intentionally unsigned: it does not contain a signing identity or
provisioning profile and cannot be installed on an iPhone through the normal
system installer until it is signed for a device.

## GitHub Actions macOS build

The same Xcode target has `SUPPORTS_MACCATALYST = YES` and
`MACOSX_DEPLOYMENT_TARGET = 15.0`. The separate manual workflow at
`.github/workflows/build-macos-catalyst.yml` builds the Mac Catalyst client on
macOS 15 (Sequoia) and uploads the
`codex-local-remote-macos-unsigned` artifact. It contains an unsigned
`Codex Local Remote.app` with arm64 and x86_64 slices. Unzip it before opening;
macOS may require an explicit right-click **Open** or removal of the quarantine
attribute because the app is unsigned. A separate macOS host/runtime remains
outside this project boundary.

Real-device acceptance must cover login cookies, CSRF recovery, SSE reconnect,
file upload/download, external links, rotation, background/foreground recovery,
and an unavailable Sidecar.
