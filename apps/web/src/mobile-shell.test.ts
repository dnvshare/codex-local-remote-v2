import { describe, expect, it } from "vitest";
import { nativeShellVoiceInputEnabled } from "./mobile-shell";

describe("native shell voice input visibility", () => {
  it("hides voice input in the Android app shell", () => {
    expect(
      nativeShellVoiceInputEnabled(
        "Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/UQ1A) AppleWebKit/537.36 Version/4.0 Chrome/120 Mobile Safari/537.36 wv CodexLocalRemoteAndroidShell",
      ),
    ).toBe(false);
  });

  it("hides voice input in the iPhone app shell", () => {
    expect(
      nativeShellVoiceInputEnabled(
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 CodexLocalRemoteIOSShell",
      ),
    ).toBe(false);
  });

  it("keeps voice input in the Mac Catalyst shell", () => {
    expect(
      nativeShellVoiceInputEnabled(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 CodexLocalRemoteIOSShell",
      ),
    ).toBe(true);
  });

  it("keeps voice input on normal web browsers", () => {
    expect(
      nativeShellVoiceInputEnabled(
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/154 Safari/537.36",
      ),
    ).toBe(true);
    expect(
      nativeShellVoiceInputEnabled(
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/154 Mobile Safari/537.36",
      ),
    ).toBe(true);
  });
});
