import type { ThreadSummary } from "@codex-local-remote/contracts";
import { currentUiLocale, uiText } from "./locale";

const effortLabels: Readonly<Record<string, string>> = {
  none: "关闭",
  minimal: "极低",
  low: "低",
  medium: "中",
  high: "高",
  max: "最高",
  xhigh: "极高",
  ultra: "ultra",
};

export function threadRuntimeSummary(
  thread: Pick<ThreadSummary, "mode" | "model" | "reasoningEffort">,
): string {
  const snapshot = thread.mode === "desktop-snapshot";
  if (!thread.model && !thread.reasoningEffort) {
    return snapshot
      ? uiText(
          "模型未知 / 思考等级未知（桌面接口未提供）",
          "Model unknown / reasoning level unavailable from Desktop",
        )
      : uiText("模型未知 / 思考等级未知", "Model unknown / reasoning level unknown");
  }
  const model =
    thread.model ??
    (snapshot
      ? uiText("模型未知（桌面接口未提供）", "Model unknown (not provided by Desktop)")
      : uiText("模型未知", "Model unknown"));
  const effortLabel = thread.reasoningEffort
    ? currentUiLocale() === "en"
      ? ((
          {
            none: "None",
            minimal: "Minimal",
            low: "Low",
            medium: "Medium",
            high: "High",
            max: "Maximum",
            xhigh: "Very high",
            ultra: "Ultra",
          } satisfies Record<string, string>
        )[thread.reasoningEffort] ?? thread.reasoningEffort)
      : (effortLabels[thread.reasoningEffort] ?? thread.reasoningEffort)
    : undefined;
  const effort = effortLabel
    ? thread.reasoningEffort === "max" || thread.reasoningEffort === "ultra"
      ? effortLabel
      : uiText(`${effortLabel}思考`, `${effortLabel} reasoning`)
    : snapshot
      ? uiText("思考等级未知（桌面接口未提供）", "Reasoning level unavailable from Desktop")
      : uiText("思考等级未知", "Reasoning level unknown");
  return `${model} · ${effort}`;
}
