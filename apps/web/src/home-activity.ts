import type { ThreadSummary } from "@codex-local-remote/contracts";
import type { StatusTone } from "@codex-local-remote/ui";
import { uiText } from "./locale";

const inactiveStates = new Set([
  "archived",
  "canceled",
  "cancelled",
  "complete",
  "completed",
  "failed",
  "idle",
  "interrupted",
  "stopped",
  "unknown",
]);

export function homeActivityThreads(threads: readonly ThreadSummary[]): ThreadSummary[] {
  return threads.filter(isHomeActivityThread);
}

export function isHomeActivityThread(thread: ThreadSummary): boolean {
  if (thread.archived || thread.parentThreadId) return false;
  return !inactiveStates.has(String(thread.state).toLowerCase());
}

export function homeActivityStateLabel(state: string): string {
  const normalized = state.trim().toLowerCase();
  const fallback = normalized.replace(/[-_]+/gu, " ").replace(/\s+/gu, " ").trim();
  const labels: Readonly<Record<string, [string, string]>> = {
    active: ["运行中", "Running"],
    "in-progress": ["运行中", "Running"],
    pending: ["等待开始", "Waiting to start"],
    queued: ["排队中", "Queued"],
    running: ["运行中", "Running"],
    starting: ["正在启动", "Starting"],
    "waiting-for-approval": ["等待审批", "Waiting for approval"],
    "waiting-for-user": ["等待用户输入", "Waiting for user input"],
    "waiting-for-user-input": ["等待用户输入", "Waiting for user input"],
  };
  const label = labels[normalized];
  return label ? uiText(label[0], label[1]) : fallback || uiText("状态未知", "Unknown status");
}

export function homeActivityStateTone(state: string): StatusTone {
  const normalized = state.toLowerCase();
  if (normalized.includes("waiting")) return "warning";
  if (normalized.includes("fail") || normalized.includes("error")) return "danger";
  if (["active", "in-progress", "running"].includes(normalized)) return "success";
  return "info";
}
