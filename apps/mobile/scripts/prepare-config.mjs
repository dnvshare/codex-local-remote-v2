import { writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const mobileRoot = resolve(import.meta.dirname, "..");

const config = {
  appId: "com.wlyaaaaa.codexlocalremote.mobile",
  appName: "Codex Local Remote",
  webDir: "dist",
  backgroundColor: "#08111f",
  ios: {
    appendUserAgent: "CodexLocalRemoteMobileShell CodexLocalRemoteIOSShell",
  },
  server: {
    allowNavigation: ["*"],
    cleartext: true,
  },
};

await writeFile(
  resolve(mobileRoot, "capacitor.config.json"),
  `${JSON.stringify(config, null, 2)}\n`,
  "utf8",
);

console.log("Prepared runtime-configurable mobile shell.");
