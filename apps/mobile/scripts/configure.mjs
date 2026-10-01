import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { normalizeMobileServerUrl } from "./server-url.mjs";

const input = process.argv[2];
if (!input) {
  throw new Error(
    "Usage: pnpm --filter @codex-local-remote/mobile configure -- https://host/codex-remote/",
  );
}

const url = normalizeMobileServerUrl(input);

const localRoot = resolve(import.meta.dirname, "..", "..", "..", ".local");
await mkdir(localRoot, { recursive: true });
await writeFile(
  resolve(localRoot, "mobile-server.json"),
  `${JSON.stringify({ serverUrl: url.toString() }, null, 2)}\n`,
  { encoding: "utf8", mode: 0o600 },
);

console.log(`Mobile server configured for ${url.origin}${url.pathname}`);
