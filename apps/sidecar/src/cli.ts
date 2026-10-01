import { realpath, stat } from "node:fs/promises";
import { pathToFileURL } from "node:url";

import { ProjectRegistry } from "@codex-local-remote/domain";

import { parseCliInvocation, resolveSidecarConfig } from "./config.js";
import { setupPassword } from "./auth.js";
import { startSidecar } from "./runtime.js";
import { SidecarStateStore } from "./state-store.js";

const HELP = `Codex Local Remote

Usage:
  codex-local-remote serve [--host lan|localhost] [--port 28790] [--app-server-url ws://127.0.0.1:28791] [--base-path /codex-remote] [--security-mode https|insecure-http] [--codex-path PATH] [--data-dir PATH] [--maintenance-token-file PATH] [--no-desktop-sync]
  codex-local-remote setup-password [--data-dir PATH]
  codex-local-remote register-project --id ID --name NAME --root PATH [--data-dir PATH]

The access password is read only from local interaction or standard input; it cannot be passed as an argument or environment variable.
The Sidecar connects only to the local shared Broker and never silently starts a second Codex backend.
The default listen mode is lan; use --host localhost to bind only to loopback.
Codex Desktop loads new conversations by default; use --no-desktop-sync to disable this.`;

export async function main(args = process.argv.slice(2)): Promise<void> {
  const invocation = parseCliInvocation(args);
  if (invocation.command === "help") {
    process.stdout.write(`${HELP}\n`);
    return;
  }

  if (invocation.command === "setup-password") {
    const config = resolveSidecarConfig({ cli: invocation.config });
    const state = await SidecarStateStore.open(config.dataDir, {
      absoluteTtlMs: config.auth.sessionAbsoluteTtlMs,
      idleTtlMs: config.auth.sessionIdleTtlMs,
    });
    const [password, confirmation] = await readPasswordPair();
    await setupPassword(state, password, confirmation, config.auth.minimumPasswordLength);
    process.stdout.write("The access password was saved securely on this computer.\n");
    return;
  }

  if (invocation.command === "register-project") {
    const config = resolveSidecarConfig({ cli: invocation.config });
    const canonicalRoot = await realpath(invocation.project.root);
    if (!(await stat(canonicalRoot)).isDirectory()) {
      throw new Error("The project path is not a directory");
    }
    const registry = new ProjectRegistry([
      {
        id: invocation.project.id,
        name: invocation.project.name,
        root: canonicalRoot,
        source: "registered",
      },
    ]);
    const project = {
      id: invocation.project.id,
      name: invocation.project.name,
      root: registry.requireRegisteredRoot(invocation.project.id),
      source: "registered" as const,
    };
    const state = await SidecarStateStore.open(config.dataDir);
    await state.registerProject(project);
    process.stdout.write("The project was added to the selectable list.\n");
    return;
  }

  const config = resolveSidecarConfig({ cli: invocation.config });
  const running = await startSidecar(config);
  process.stdout.write(
    `Codex Local Remote started at ${config.host}:${config.port}${config.basePath}/.\n`,
  );
  if (config.securityMode === "insecure-http") {
    process.stderr.write(
      "Warning: HTTP session cookies are allowed; same-origin, CSRF and password checks remain enabled.\n",
    );
  }
  await waitForShutdown(async () => {
    await running.stop();
  });
}

async function readPasswordPair(): Promise<[string, string]> {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    let input = "";
    for await (const chunk of process.stdin) {
      input += Buffer.isBuffer(chunk) ? chunk.toString("utf8") : String(chunk);
      if (input.length > 32_768) {
        throw new Error("Password input is too long");
      }
    }
    const lines = input.split(/\r?\n/u);
    if (lines.length < 2) {
      throw new Error("Provide the password twice through standard input");
    }
    return [lines[0] ?? "", lines[1] ?? ""];
  }
  const first = await readHiddenLine("Enter the new access password: ");
  const second = await readHiddenLine("Enter the access password again: ");
  return [first, second];
}

async function readHiddenLine(prompt: string): Promise<string> {
  process.stdout.write(prompt);
  process.stdin.setRawMode(true);
  process.stdin.resume();
  process.stdin.setEncoding("utf8");
  let value = "";
  try {
    return await new Promise<string>((resolve, reject) => {
      const onData = (chunk: string) => {
        for (const character of chunk) {
          if (character === "\r" || character === "\n") {
            process.stdin.off("data", onData);
            process.stdout.write("\n");
            resolve(value);
            return;
          }
          if (character === "\u0003") {
            process.stdin.off("data", onData);
            reject(new Error("Operation cancelled"));
            return;
          }
          if (character === "\u007F" || character === "\b") {
            value = value.slice(0, -1);
          } else if (value.length < 16_384 && character >= " ") {
            value += character;
          }
        }
      };
      process.stdin.on("data", onData);
    });
  } finally {
    process.stdin.setRawMode(false);
    process.stdin.pause();
  }
}

async function waitForShutdown(stop: () => Promise<void>): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    let stopping = false;
    const shutdown = () => {
      if (stopping) {
        return;
      }
      stopping = true;
      void stop().then(resolve, reject);
    };
    process.once("SIGINT", shutdown);
    process.once("SIGTERM", shutdown);
  });
}

const invokedPath = process.argv[1];
if (invokedPath && pathToFileURL(invokedPath).href === import.meta.url) {
  void main().catch((error: unknown) => {
    const code = startupFailureCode(error);
    process.stderr.write(`${startupFailureMessage(error, code)}[${code}]\n`);
    process.exitCode = 1;
  });
}

function startupFailureMessage(error: unknown, code: string): string {
  if ((code === "PASSWORD_MISMATCH" || code === "PASSWORD_POLICY") && error instanceof Error) {
    return `${error.message}。`;
  }
  return "Codex Local Remote could not start; check the local settings and try again.";
}

function startupFailureCode(error: unknown): string {
  if (error instanceof Error && error.message === "The remote message queue could not be read") {
    return "QUEUE_READ_FAILED";
  }
  const code =
    typeof error === "object" && error !== null && "code" in error
      ? (error as { code?: unknown }).code
      : undefined;
  return typeof code === "string" && /^[A-Z0-9_]{2,64}$/u.test(code) ? code : "STARTUP_FAILED";
}
