import type { UsageCredits, UsageSnapshot, UsageWindow } from "@codex-local-remote/contracts";
import { uiText } from "./locale";

export type QuotaPresentation = {
  state: "available" | "warning" | "exhausted" | "unknown";
  usedPercent?: number;
  message?: string;
};

export type ContextPresentation = {
  state: "available" | "unknown";
  usedPercent?: number;
};

export type CodexAccountPresentation = {
  detail: string;
  status: string;
  tone: "success" | "warning";
};

export function codexAccountPresentation(
  usage: UsageSnapshot | undefined,
): CodexAccountPresentation {
  const account = usage?.codexAccount;
  if (!account) {
    return {
      detail:
        usage?.availability?.account === "available"
          ? uiText(
              "Codex 未提供可显示的账号名称",
              "Codex did not provide a displayable account name",
            )
          : uiText("账号信息暂时无法读取", "Account information is temporarily unavailable"),
      status: uiText("暂时不可用", "Unavailable"),
      tone: "warning",
    };
  }
  if (account.type === "chatgpt") {
    return {
      detail: account.email ?? uiText("ChatGPT 账号", "ChatGPT account"),
      status: usage?.plan?.trim() || uiText("已登录", "Signed in"),
      tone: "success",
    };
  }
  return {
    detail: account.type === "apiKey" ? "OpenAI API Key" : "Amazon Bedrock",
    status: uiText("已配置", "Configured"),
    tone: "success",
  };
}

export function usageAvailabilityMessage(usage: UsageSnapshot | undefined): string | undefined {
  const availability = usage?.availability;
  if (!availability) return undefined;
  const accountUnavailable = availability.account === "temporarily-unavailable";
  const rateLimitsUnavailable = availability.rateLimits === "temporarily-unavailable";
  const tokenUsageUnavailable = availability.tokenUsage === "temporarily-unavailable";
  if (!accountUnavailable && !rateLimitsUnavailable && !tokenUsageUnavailable) return undefined;
  if (accountUnavailable && !rateLimitsUnavailable && !tokenUsageUnavailable) {
    return uiText(
      "Codex 账号信息暂时无法读取。额度与 Token 用量仍可继续显示。",
      "Codex account information is temporarily unavailable. Usage and token data may still be shown.",
    );
  }
  const unavailableParts = [
    ...(accountUnavailable ? [uiText("账号", "account")] : []),
    ...(rateLimitsUnavailable ? [uiText("额度、Credits", "usage and credits")] : []),
    ...(tokenUsageUnavailable ? [uiText("Token 用量", "token usage")] : []),
  ];
  const joined =
    unavailableParts.length > 1
      ? uiText(
          `${unavailableParts.slice(0, -1).join("、")} 与 ${unavailableParts.at(-1)}`,
          `${unavailableParts.slice(0, -1).join(", ")} and ${unavailableParts.at(-1)}`,
        )
      : unavailableParts[0];
  return accountUnavailable
    ? uiText(
        `Codex ${joined}暂时无法读取。请检查电脑的系统网络或代理后重试。`,
        `Codex ${joined} is temporarily unavailable. Check the computer's network or proxy and try again.`,
      )
    : uiText(
        `Codex 已登录，但${joined}暂时无法读取。请检查电脑的系统网络或代理后重试。`,
        `Codex is signed in, but ${joined} is temporarily unavailable. Check the computer's network or proxy and try again.`,
      );
}

export function usedPercentLabel(value: number | undefined): string {
  return value === undefined
    ? uiText("已用比例暂时无法读取", "Used percentage unavailable")
    : uiText(`已用 ${Math.round(value)}%`, `${Math.round(value)}% used`);
}

export function remainingPercentLabel(value: number | undefined): string {
  return value === undefined
    ? uiText("剩余额度暂时无法读取", "Remaining usage unavailable")
    : uiText(`剩余额度 ${Math.round(value)}%`, `${Math.round(value)}% remaining`);
}

export function remainingContextPercentLabel(value: number | undefined): string {
  return value === undefined
    ? uiText("剩余上下文暂时无法读取", "Remaining context unavailable")
    : uiText(`剩余上下文 ${Math.round(value)}%`, `${Math.round(value)}% context remaining`);
}

export function remainingFromUsedPercent(value: number | undefined): number | undefined {
  return value === undefined ? undefined : Math.max(0, Math.min(100, 100 - value));
}

export function creditBalanceLabel(credit: UsageCredits): string {
  if (credit.unlimited) return uiText("额外 Credits 不限", "Unlimited extra credits");
  if (!credit.hasCredits) return uiText("无额外 Credits", "No extra credits");
  return credit.balance === undefined
    ? uiText("额外 Credits 余额暂时无法读取", "Extra credit balance unavailable")
    : uiText(`额外 Credits 余额 ${credit.balance}`, `Extra credit balance: ${credit.balance}`);
}

export function usageWindowForDisplay(
  windows: readonly UsageWindow[] | undefined,
  preferredModel?: string,
): UsageWindow | undefined {
  if (!windows?.length) return undefined;
  const model = preferredModel?.trim().toLocaleLowerCase("en-US");
  if (model) {
    const exactModelWindow = windows.find((window) =>
      window.label.toLocaleLowerCase("en-US").includes(model),
    );
    if (exactModelWindow) return exactModelWindow;
  }
  return [...windows].sort((left, right) => {
    const leftGeneric = /^codex(?:\s|·|$)/iu.test(left.label) ? 0 : 1;
    const rightGeneric = /^codex(?:\s|·|$)/iu.test(right.label) ? 0 : 1;
    return leftGeneric - rightGeneric || left.id.localeCompare(right.id, "en-US");
  })[0];
}

export function formatUtc8Time(value?: string): string {
  if (!value) return uiText("暂时无法读取", "Unavailable");
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return uiText("暂时无法读取", "Unavailable");
  const locale = uiText("zh-CN", "en-US");
  const parts = new Intl.DateTimeFormat(locale, {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "numeric",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  })
    .formatToParts(date)
    .reduce<Record<string, string>>((result, part) => {
      if (part.type !== "literal") result[part.type] = part.value;
      return result;
    }, {});
  if (!parts.year || !parts.month || !parts.day || !parts.hour || !parts.minute) {
    return uiText("暂时无法读取", "Unavailable");
  }
  return uiText(
    `${parts.year}年${Number(parts.month)}月${Number(parts.day)}日 ${parts.hour}:${parts.minute}（UTC+8）`,
    `${parts.month}/${parts.day}/${parts.year} ${parts.hour}:${parts.minute} (UTC+8)`,
  );
}

export function quotaPresentation(
  usage: UsageSnapshot | undefined,
  preferredModel?: string,
): QuotaPresentation {
  const window = usageWindowForDisplay(usage?.windows, preferredModel);
  const usedPercent =
    window?.usedPercent === undefined ? undefined : Math.max(0, Math.min(100, window.usedPercent));
  if (usedPercent !== undefined && (usedPercent >= 100 || window?.remainingPercent === 0)) {
    return {
      state: "exhausted",
      usedPercent,
      message: uiText("当前额度已用完", "The current usage limit is exhausted"),
    };
  }
  if (usedPercent !== undefined && usedPercent >= 85) {
    return {
      state: "warning",
      usedPercent,
      message: uiText("当前额度即将用完", "The current usage limit is nearly exhausted"),
    };
  }
  if (usedPercent === undefined) {
    return {
      state: "unknown",
      message: uiText("额度暂时无法读取", "Usage is temporarily unavailable"),
    };
  }
  return {
    state: "available",
    usedPercent,
  };
}

export function contextPresentation(usage: UsageSnapshot | undefined): ContextPresentation {
  const context = usage?.context;
  const calculatedPercent =
    context?.usedTokens !== undefined &&
    context.limitTokens !== undefined &&
    context.limitTokens > 0
      ? (context.usedTokens / context.limitTokens) * 100
      : undefined;
  const usedPercent = calculatedPercent ?? context?.usedPercent;
  if (usedPercent === undefined) {
    return { state: "unknown" };
  }
  return {
    state: "available",
    usedPercent: Math.max(0, Math.min(100, usedPercent)),
  };
}

export function contextUsageOrbLabel(
  presentation: ContextPresentation,
  refreshing: boolean,
): string {
  if (refreshing) return uiText("正在刷新额度与上下文", "Refreshing usage and context");
  if (presentation.usedPercent === undefined) {
    return uiText(
      "当前上下文暂时无法读取，点按查看额度与上下文",
      "Context is temporarily unavailable; open usage and context details",
    );
  }
  return uiText(
    `当前上下文已用 ${Math.round(presentation.usedPercent)}%，点按查看额度与上下文`,
    `${Math.round(presentation.usedPercent)}% of context used; open usage and context details`,
  );
}
