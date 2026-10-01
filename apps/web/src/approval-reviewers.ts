import type { ApprovalReviewerOption } from "@codex-local-remote/contracts";
import { uiText } from "./locale";

/**
 * Presentation labels do not define availability. The running Codex
 * requirements catalog remains the only source of reviewer ids.
 */
export function approvalReviewerLabel(id: string): string {
  switch (id) {
    case "user":
      return uiText("我来确认", "I will review");
    case "auto_review":
      return uiText("Codex 自动确认", "Codex automatic review");
    case "guardian_subagent":
      return uiText("安全智能体代我确认", "Safety subagent reviews for me");
    default:
      return id;
  }
}

export function approvalReviewerDescription(id: string): string {
  switch (id) {
    case "user":
      return uiText(
        "审批会同步到 Desktop 和手机，由你同意或拒绝。",
        "Approvals are shared with Desktop and mobile for you to accept or reject.",
      );
    case "auto_review":
      return uiText(
        "由 Codex 按当前安全规则自动决定。",
        "Codex decides automatically using the current safety rules.",
      );
    case "guardian_subagent":
      return uiText(
        "由独立的安全检查智能体判断是否允许。",
        "An independent safety subagent decides whether to allow it.",
      );
    default:
      return uiText(
        `由当前 Codex 运行时提供：${id}`,
        `Provided by the current Codex runtime: ${id}`,
      );
  }
}

export function chooseApprovalReviewer(
  options: readonly ApprovalReviewerOption[],
  preferred?: string | null,
): string {
  if (preferred && options.some((option) => option.id === preferred)) {
    return preferred;
  }
  return options[0]?.id ?? "";
}
