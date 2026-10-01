import type { ApprovalPolicyOption } from "@codex-local-remote/contracts";
import { uiText } from "./locale";

export function approvalPolicyLabel(id: string): string {
  const labels: Readonly<Record<string, [string, string]>> = {
    never: ["自动允许，不再询问", "Always allow without asking"],
    "on-request": ["仅在需要时询问我", "Ask me only when needed"],
    untrusted: ["每次都询问我", "Ask me every time"],
  };
  const label = labels[id];
  return label ? uiText(label[0], label[1]) : id;
}

export function approvalPolicyDescription(id: string): string {
  const descriptions: Readonly<Record<string, [string, string]>> = {
    never: ["Codex 不会停下来等待你的确认。", "Codex will not stop to ask for confirmation."],
    "on-request": [
      "遇到可能有风险的操作时停下来询问你。",
      "Codex will pause and ask when an operation may be risky.",
    ],
    untrusted: [
      "每个需要授权的操作都等你确认。",
      "Every operation that needs authorization waits for your confirmation.",
    ],
  };
  const description = descriptions[id];
  return description
    ? uiText(description[0], description[1])
    : uiText(`由当前 Codex 运行时提供：${id}`, `Provided by the current Codex runtime: ${id}`);
}

export function chooseApprovalPolicy(
  options: readonly ApprovalPolicyOption[],
  preferred?: string | null,
): string {
  if (preferred && options.some((option) => option.id === preferred)) {
    return preferred;
  }
  return options.find((option) => option.id === "on-request")?.id ?? options[0]?.id ?? "";
}
