import type { RunState } from "@codex-local-remote/contracts";
import { uiText } from "./locale";

const PRODUCT_TITLE = "Codex Local Remote";
const MAX_THREAD_TITLE_LENGTH = 32;

export interface BrowserAttentionInput {
  approvalCount: number;
  currentState?: RunState;
  currentTitle?: string;
  online: boolean;
  runningCount: number;
}

export function browserAttentionTitle(input: BrowserAttentionInput): string {
  if (!input.online)
    return uiText(`实时更新中断 · ${PRODUCT_TITLE}`, `Live updates interrupted · ${PRODUCT_TITLE}`);

  const approvalCount = boundedCount(input.approvalCount);
  if (approvalCount > 0) {
    return uiText(
      `(${approvalCount}) 等待处理 · ${PRODUCT_TITLE}`,
      `(${approvalCount}) Needs attention · ${PRODUCT_TITLE}`,
    );
  }

  const currentTitle = compactThreadTitle(input.currentTitle);
  if (input.currentState === "waiting-for-approval") {
    return currentTitle
      ? uiText(
          `等待处理 · ${currentTitle} · Codex Remote`,
          `Needs attention · ${currentTitle} · Codex Remote`,
        )
      : uiText(`等待处理 · ${PRODUCT_TITLE}`, `Needs attention · ${PRODUCT_TITLE}`);
  }
  if (input.currentState === "running") {
    return currentTitle
      ? uiText(
          `运行中 · ${currentTitle} · Codex Remote`,
          `Running · ${currentTitle} · Codex Remote`,
        )
      : uiText(`运行中 · ${PRODUCT_TITLE}`, `Running · ${PRODUCT_TITLE}`);
  }
  if (input.currentState === "failed") {
    return currentTitle
      ? uiText(
          `任务失败 · ${currentTitle} · Codex Remote`,
          `Task failed · ${currentTitle} · Codex Remote`,
        )
      : uiText(`任务失败 · ${PRODUCT_TITLE}`, `Task failed · ${PRODUCT_TITLE}`);
  }
  if (input.currentState === "interrupted") {
    return currentTitle
      ? uiText(
          `任务已中断 · ${currentTitle} · Codex Remote`,
          `Task interrupted · ${currentTitle} · Codex Remote`,
        )
      : uiText(`任务已中断 · ${PRODUCT_TITLE}`, `Task interrupted · ${PRODUCT_TITLE}`);
  }

  const runningCount = boundedCount(input.runningCount);
  if (runningCount > 0) {
    return uiText(
      `(${runningCount}) 运行中 · ${PRODUCT_TITLE}`,
      `(${runningCount}) Running · ${PRODUCT_TITLE}`,
    );
  }
  return currentTitle ? `${currentTitle} · Codex Remote` : PRODUCT_TITLE;
}

function boundedCount(value: number): number {
  if (!Number.isFinite(value) || value <= 0) return 0;
  return Math.min(99, Math.floor(value));
}

function compactThreadTitle(value: string | undefined): string {
  const normalized = value?.replace(/\s+/gu, " ").trim() ?? "";
  if (normalized.length <= MAX_THREAD_TITLE_LENGTH) return normalized;
  return `${normalized.slice(0, MAX_THREAD_TITLE_LENGTH - 1)}…`;
}
