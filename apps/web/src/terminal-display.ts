import type { ThreadDetail } from "@codex-local-remote/contracts";
import { uiText } from "./locale";

type ToolItem = Extract<ThreadDetail["items"][number], { kind: "tool" }>;
type FileChangeItem = Extract<ThreadDetail["items"][number], { kind: "file-change" }>;

function changeLabel(change: FileChangeItem["change"]): string {
  if (change === "added") return uiText("新增", "Added");
  if (change === "deleted") return uiText("删除", "Deleted");
  return uiText("修改", "Modified");
}

export function toolFallbackSummary(status: ToolItem["status"]): string {
  if (status === "running") return uiText("正在执行", "Running");
  if (status === "failed") return uiText("执行失败", "Failed");
  return uiText("已完成", "Completed");
}

export function fileChangeStatusLabel(
  change: FileChangeItem["change"],
  status: NonNullable<FileChangeItem["status"]> = "completed",
): string {
  const action = changeLabel(change);
  if (status === "inProgress") return `${uiText("正在", "In progress: ")}${action}`;
  if (status === "failed") return uiText(`${action}失败`, `${action} failed`);
  if (status === "declined") return uiText(`已拒绝${action}`, `Declined ${action}`);
  return action;
}
