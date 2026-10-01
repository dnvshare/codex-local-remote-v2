import type { ConversationItem } from "@codex-local-remote/contracts";
import { currentUiLocale, uiText } from "./locale";

export type ConversationSegment =
  | { kind: "content"; item: ConversationItem }
  | { kind: "work"; items: ConversationItem[] }
  | { kind: "compaction"; item: Extract<ConversationItem, { kind: "tool" }> };

export function isShellToolTitle(title: string | undefined): boolean {
  return title === "运行命令" || title === "Run command";
}

export function isImageToolTitle(title: string | undefined): boolean {
  return title === "查看图片" || title === "View image";
}

export function activityTitleForDisplay(title: string | undefined): string | undefined {
  if (title === undefined) return undefined;
  const labels: Readonly<Record<string, readonly [string, string]>> = {
    "Codex 提出了问题": ["Codex 提出了问题", "Codex asked a question"],
    "Codex asked a question": ["Codex 提出了问题", "Codex asked a question"],
    运行命令: ["运行命令", "Run command"],
    "Run command": ["运行命令", "Run command"],
    修改文件: ["修改文件", "Edit files"],
    "Edit files": ["修改文件", "Edit files"],
    更新计划: ["更新计划", "Update plan"],
    "Update plan": ["更新计划", "Update plan"],
    管理任务: ["管理任务", "Manage task"],
    "Manage task": ["管理任务", "Manage task"],
    协作任务: ["协作任务", "Collaborative task"],
    "Collaborative task": ["协作任务", "Collaborative task"],
    查看图片: ["查看图片", "View image"],
    "View image": ["查看图片", "View image"],
    生成图片: ["生成图片", "Generate image"],
    "Generate image": ["生成图片", "Generate image"],
    等待操作: ["等待操作", "Wait for operation"],
    "Wait for operation": ["等待操作", "Wait for operation"],
    使用工具: ["使用工具", "Use tool"],
    "Use tool": ["使用工具", "Use tool"],
    查找可用工具: ["查找可用工具", "Search available tools"],
    "Search available tools": ["查找可用工具", "Search available tools"],
    压缩对话上下文: ["压缩对话上下文", "Compress conversation context"],
    "Compress conversation context": ["压缩对话上下文", "Compress conversation context"],
  };
  const pair = labels[title];
  return pair === undefined ? title : uiText(pair[0], pair[1]);
}

export function groupConversationItems(items: readonly ConversationItem[]): ConversationSegment[] {
  const segments: ConversationSegment[] = [];
  for (const item of items) {
    if (item.kind === "tool" && item.operation === "context-compaction") {
      segments.push({ kind: "compaction", item });
      continue;
    }
    if (!isWorkLogItem(item)) {
      segments.push({ kind: "content", item });
      continue;
    }
    const previous = segments.at(-1);
    if (previous?.kind === "work" && workSegmentAcceptsItem(previous.items, item)) {
      previous.items.push(item);
      continue;
    }
    segments.push({ kind: "work", items: [item] });
  }
  return segments;
}

function isWorkLogItem(item: ConversationItem): boolean {
  return (
    item.kind === "reasoning-summary" ||
    (item.kind === "assistant-message" && item.phase === "commentary") ||
    item.kind === "tool" ||
    item.kind === "file-change" ||
    item.kind === "subagent-activity"
  );
}

export function activitySummary(items: readonly ConversationItem[]): string {
  let commands = 0;
  let files = 0;
  let images = 0;
  let other = 0;
  for (const item of items) {
    if (item.kind === "file-change") {
      files += 1;
    } else if (item.kind === "tool" && isShellToolTitle(item.title)) {
      commands += item.occurrences ?? 1;
    } else if (item.kind === "tool" && isImageToolTitle(item.title)) {
      images += item.occurrences ?? 1;
    } else if (item.kind === "tool") {
      other += item.occurrences ?? 1;
    }
  }
  const parts: string[] = [];
  if (files)
    parts.push(
      uiText(`编辑了 ${files} 个文件`, `Edited ${files} ${files === 1 ? "file" : "files"}`),
    );
  if (commands)
    parts.push(
      uiText(
        `运行了 ${commands} 个命令`,
        `Ran ${commands} ${commands === 1 ? "command" : "commands"}`,
      ),
    );
  if (images)
    parts.push(
      uiText(`查看了 ${images} 张图像`, `Viewed ${images} ${images === 1 ? "image" : "images"}`),
    );
  if (other)
    parts.push(
      uiText(`完成了 ${other} 项操作`, `Completed ${other} ${other === 1 ? "action" : "actions"}`),
    );
  return parts.length ? parts.join(" · ") : uiText("工作记录", "Work log");
}

export function workLogSummary(items: readonly ConversationItem[]): string {
  let thoughts = 0;
  let operations = 0;
  const agentIds = new Set<string>();
  for (const item of items) {
    if (
      item.kind === "reasoning-summary" ||
      (item.kind === "assistant-message" && item.phase === "commentary")
    ) {
      thoughts += 1;
    } else if (item.kind === "tool") {
      operations += item.occurrences ?? 1;
    } else if (item.kind === "file-change") {
      operations += 1;
    } else if (item.kind === "subagent-activity") {
      for (const agent of item.agents) agentIds.add(agent.threadId);
    }
  }
  const parts: string[] = [];
  if (thoughts)
    parts.push(
      uiText(`${thoughts} 条进展`, `${thoughts} ${thoughts === 1 ? "update" : "updates"}`),
    );
  if (operations)
    parts.push(
      uiText(`${operations} 项操作`, `${operations} ${operations === 1 ? "action" : "actions"}`),
    );
  if (agentIds.size)
    parts.push(
      uiText(
        `${agentIds.size} 个子智能体`,
        `${agentIds.size} ${agentIds.size === 1 ? "subagent" : "subagents"}`,
      ),
    );
  return parts.length ? parts.join(" · ") : uiText("工作记录", "Work log");
}

export function workLogHeadline(items: readonly ConversationItem[]): string | undefined {
  const latestThought = items.findLast(
    (item) =>
      item.kind === "reasoning-summary" ||
      (item.kind === "assistant-message" && item.phase === "commentary"),
  );
  if (latestThought?.kind !== "reasoning-summary" && latestThought?.kind !== "assistant-message") {
    return undefined;
  }
  const text = latestReasoningText(latestThought.text);
  if (text === undefined) return undefined;
  return text.length <= 120 ? text : `${text.slice(0, 119).trimEnd()}…`;
}

export function activeWorkLogSegmentIndex(
  segments: readonly ConversationSegment[],
  activeTurnId: string | undefined,
): number {
  if (activeTurnId === undefined) return -1;
  const exactIndex = segments.findLastIndex(
    (segment) =>
      segment.kind === "work" && segment.items.some((item) => item.turnId === activeTurnId),
  );
  if (exactIndex >= 0) return exactIndex;
  const latestUserIndex = segments.findLastIndex(
    (segment) => segment.kind === "content" && segment.item.kind === "user-message",
  );
  if (latestUserIndex < 0) return -1;
  return segments.findLastIndex(
    (segment, index) => index > latestUserIndex && segment.kind === "work",
  );
}

export function workLogSegmentBelongsToActiveTurn(
  segments: readonly ConversationSegment[],
  segmentIndex: number,
  activeTurnId: string | undefined,
): boolean {
  if (activeTurnId === undefined) return false;
  const segment = segments[segmentIndex];
  if (segment?.kind !== "work") return false;
  const explicitTurnIds = segment.items.flatMap((item) =>
    item.turnId === undefined ? [] : [item.turnId],
  );
  if (explicitTurnIds.includes(activeTurnId)) return true;
  if (explicitTurnIds.length > 0) return false;
  const latestUserIndex = segments.findLastIndex(
    (candidate) => candidate.kind === "content" && candidate.item.kind === "user-message",
  );
  return latestUserIndex >= 0 && segmentIndex > latestUserIndex;
}

export function subagentActivityStatusForDisplay(
  status: Extract<ConversationItem, { kind: "subagent-activity" }>["status"],
  active: boolean,
  action?: Extract<ConversationItem, { kind: "subagent-activity" }>["action"],
): Extract<ConversationItem, { kind: "subagent-activity" }>["status"] | "unknown" {
  if (status === "failed") return "failed";
  if (status === "complete" || action === "close") return "complete";
  return active ? "running" : "unknown";
}

export function assistantPhaseForDisplay(
  item: ConversationItem,
  items: readonly ConversationItem[],
): "commentary" | "final_answer" | undefined {
  if (item.kind !== "assistant-message") return undefined;
  if (item.phase) return item.phase;
  const sameTurnAssistantItems = items.filter(
    (candidate) =>
      candidate.kind === "assistant-message" &&
      (item.turnId === undefined || candidate.turnId === item.turnId),
  );
  return sameTurnAssistantItems.at(-1)?.id === item.id ? "final_answer" : "commentary";
}

export function conversationContentItems(
  items: readonly ConversationItem[],
  _activeTurnId?: string,
): ConversationItem[] {
  return items.filter((item) => {
    if (item.kind === "plan-progress") {
      return false;
    }
    if (item.kind === "reasoning-summary") {
      return false;
    }
    if (item.kind !== "assistant-message") {
      return true;
    }
    const formalPlan = items.find(
      (candidate): candidate is Extract<ConversationItem, { kind: "formal-plan" }> =>
        candidate.kind === "formal-plan" && candidate.turnId === item.turnId,
    );
    return (
      formalPlan === undefined ||
      normalizePlanText(extractProposedPlan(item.text)) !== normalizePlanText(formalPlan.text)
    );
  });
}

export function latestPlanProgress(
  items: readonly ConversationItem[],
): Extract<ConversationItem, { kind: "plan-progress" }> | undefined {
  for (let index = items.length - 1; index >= 0; index -= 1) {
    const item = items[index];
    if (item?.kind === "plan-progress") {
      return item.steps.length > 0 ? item : undefined;
    }
  }
  return undefined;
}

export function latestComposerPlanProgress(
  items: readonly ConversationItem[],
  activeTurnId: string | undefined,
): Extract<ConversationItem, { kind: "plan-progress" }> | undefined {
  if (!activeTurnId) return undefined;
  for (let index = items.length - 1; index >= 0; index -= 1) {
    const item = items[index];
    if (item?.kind === "plan-progress" && item.turnId === activeTurnId) {
      return item.steps.length > 0 ? item : undefined;
    }
  }
  return undefined;
}

export function latestActiveReasoning(
  items: readonly ConversationItem[],
  activeTurnId: string | undefined,
): { id: string; text: string } | undefined {
  if (activeTurnId === undefined) {
    return undefined;
  }
  const latestUserIndex = latestUserMessageIndex(items);
  const oldestCandidateIndex = latestUserIndex < 0 ? 0 : latestUserIndex + 1;
  for (let index = items.length - 1; index >= oldestCandidateIndex; index -= 1) {
    const item = items[index];
    if (
      item?.kind === "reasoning-summary" &&
      (item.turnId === activeTurnId || (item.turnId === undefined && latestUserIndex >= 0))
    ) {
      return { id: item.id, text: item.text };
    }
  }
  return undefined;
}

export function latestReasoningText(text: string): string | undefined {
  const lines = text
    .replace(/\r\n?/gu, "\n")
    .split(/\n+/u)
    .map((line) => line.trim())
    .filter(Boolean);
  const latest = lines.at(-1);
  if (latest === undefined) return undefined;
  return latest
    .replace(/^(?:\*\*|__)(.+)(?:\*\*|__)$/u, "$1")
    .replace(/^`(.+)`$/u, "$1")
    .trim();
}

export type LiveConversationPhase =
  | { kind: "activity"; text: string }
  | { kind: "reasoning"; text: string };

export function currentLivePhase(
  items: readonly ConversationItem[],
  activeTurnId: string | undefined,
): LiveConversationPhase | undefined {
  if (activeTurnId === undefined) {
    return undefined;
  }
  const latestUserIndex = latestUserMessageIndex(items);
  const belongsToActiveTurn = (item: ConversationItem, index: number) =>
    item.turnId === activeTurnId ||
    (item.turnId === undefined && latestUserIndex >= 0 && index > latestUserIndex);

  for (let index = items.length - 1; index >= 0; index -= 1) {
    const item = items[index];
    if (item === undefined || !belongsToActiveTurn(item, index)) {
      continue;
    }
    if (
      item.kind === "tool" &&
      (item.status === "running" ||
        item.occurrenceDetails?.some((occurrence) => occurrence.status === "running"))
    ) {
      return { kind: "activity", text: runningToolLabel(item.title, item.operation) };
    }
    if (item.kind === "file-change" && item.status === "inProgress") {
      return {
        kind: "activity",
        text:
          item.change === "added"
            ? uiText("正在创建文件", "Creating file")
            : item.change === "deleted"
              ? uiText("正在删除文件", "Deleting file")
              : uiText("正在编辑文件", "Editing file"),
      };
    }
    if (item.kind === "subagent-activity" && item.status === "running") {
      return { kind: "activity", text: uiText("子智能体正在工作", "Subagent is working") };
    }
  }

  for (let index = items.length - 1; index >= 0; index -= 1) {
    const item = items[index];
    if (item === undefined || !belongsToActiveTurn(item, index)) {
      continue;
    }
    if (latestUserIndex >= 0 && index <= latestUserIndex) {
      return undefined;
    }
    if (item.kind === "reasoning-summary") {
      const text = latestReasoningText(item.text);
      if (text === undefined) {
        return undefined;
      }
      return {
        kind: "reasoning",
        text,
      };
    }
    if (item.kind === "assistant-message") {
      return undefined;
    }
    if (
      item.kind === "tool" ||
      item.kind === "file-change" ||
      item.kind === "subagent-activity" ||
      item.kind === "plan-progress"
    ) {
      return undefined;
    }
  }
  return undefined;
}

function latestUserMessageIndex(items: readonly ConversationItem[]): number {
  return items.findLastIndex((item) => item.kind === "user-message");
}

function runningToolLabel(
  title: string,
  operation: Extract<ConversationItem, { kind: "tool" }>["operation"],
): string {
  if (operation === "context-compaction") {
    return uiText("正在压缩上下文", "Compacting context");
  }
  const normalized = title.trim();
  if (isShellToolTitle(normalized)) {
    return uiText("正在运行命令", "Running command");
  }
  if (normalized === "使用连接工具" || normalized === "Using connection tool") {
    return uiText("正在使用连接工具", "Using connection tool");
  }
  if (normalized === "使用工具" || normalized === "Use tool") {
    return uiText("正在使用工具", "Using tool");
  }
  if (normalized.includes("编辑") || normalized.includes("修改") || normalized.includes("Edit")) {
    return uiText("正在编辑文件", "Editing file");
  }
  if (normalized.startsWith("正在")) {
    return currentUiLocale() === "en" ? normalized.replace(/^正在/u, "") : normalized;
  }
  return normalized.length > 0
    ? uiText(`正在${normalized}`, `Working on ${normalized}`)
    : uiText("正在执行操作", "Performing operation");
}

function workSegmentAcceptsItem(
  segmentItems: readonly ConversationItem[],
  item: ConversationItem,
): boolean {
  if (segmentItems.length === 0) return false;
  if (item.turnId === undefined) return true;
  const explicitTurnId = segmentItems.find((candidate) => candidate.turnId !== undefined)?.turnId;
  return explicitTurnId === undefined || explicitTurnId === item.turnId;
}

function extractProposedPlan(text: string): string {
  const match = /<proposed_plan>\s*([\s\S]*?)\s*<\/proposed_plan>/iu.exec(text);
  return match?.[1] ?? text;
}

function normalizePlanText(text: string): string {
  return text.replace(/\r\n?/gu, "\n").replace(/\s+/gu, " ").trim();
}
