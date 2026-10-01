import type { ThreadDetail, ThreadSettingsInput } from "@codex-local-remote/contracts";
import { uiText } from "./locale";

const settingLabels = {
  model: ["模型", "Model"],
  reasoningEffort: ["思考等级", "Reasoning level"],
  serviceTier: ["速度", "Speed"],
  permissionProfileId: ["文件与命令权限", "File and command permissions"],
  approvalPolicy: ["确认时机", "Approval timing"],
  approvalsReviewer: ["审批方式", "Approval reviewer"],
  collaborationMode: ["协作模式", "Collaboration mode"],
} satisfies Record<keyof ThreadSettingsInput, readonly [string, string]>;

const settingKeys = Object.keys(settingLabels) as Array<keyof ThreadSettingsInput>;

function normalizedSetting(value: string | null | undefined): string | undefined {
  return value === null || value === "" ? undefined : value;
}

export type ThreadSettingsReadbackOptions = {
  requested: ThreadSettingsInput;
  read: () => Promise<ThreadDetail>;
  retryDelaysMs?: readonly number[];
  wait?: (delayMs: number) => Promise<void>;
};

export type ThreadSettingsReadbackResult = {
  authoritative: ThreadDetail;
  mismatches: string[];
};

/**
 * A successful settings mutation is the protocol acknowledgement. The first
 * detail read can still contain the previous turn's snapshot, so keep the
 * accepted values when refreshing the product projection.
 */
export function applyAcceptedThreadSettings(
  authoritative: ThreadDetail,
  requested: ThreadSettingsInput,
): ThreadDetail {
  const next = { ...authoritative };
  if (requested.model !== undefined) {
    if (requested.model === null) delete next.model;
    else next.model = requested.model;
  }
  if (requested.reasoningEffort !== undefined) {
    if (requested.reasoningEffort === null) delete next.reasoningEffort;
    else next.reasoningEffort = requested.reasoningEffort;
  }
  if (requested.serviceTier !== undefined) {
    if (requested.serviceTier === null) delete next.serviceTier;
    else next.serviceTier = requested.serviceTier;
  }
  if (requested.permissionProfileId !== undefined) {
    if (requested.permissionProfileId === null) delete next.permissionProfileId;
    else next.permissionProfileId = requested.permissionProfileId;
  }
  if (requested.approvalPolicy !== undefined) {
    if (requested.approvalPolicy === null) delete next.approvalPolicy;
    else next.approvalPolicy = requested.approvalPolicy;
  }
  if (requested.approvalsReviewer !== undefined) {
    if (requested.approvalsReviewer === null) delete next.approvalsReviewer;
    else next.approvalsReviewer = requested.approvalsReviewer;
  }
  if (requested.collaborationMode !== undefined) {
    if (requested.collaborationMode === null) delete next.collaborationMode;
    else next.collaborationMode = requested.collaborationMode;
  }
  return next;
}

export function threadSettingsReadbackMismatches(
  requested: ThreadSettingsInput,
  authoritative: ThreadDetail,
): string[] {
  return settingKeys.flatMap((key) => {
    if (requested[key] === undefined) return [];
    return normalizedSetting(requested[key]) === normalizedSetting(authoritative[key])
      ? []
      : [uiText(settingLabels[key][0], settingLabels[key][1])];
  });
}

export async function readThreadSettingsUntilConverged({
  requested,
  read,
  retryDelaysMs = [150, 300, 600, 1_000],
  wait = (delayMs) =>
    new Promise<void>((resolve) => {
      setTimeout(resolve, delayMs);
    }),
}: ThreadSettingsReadbackOptions): Promise<ThreadSettingsReadbackResult> {
  let authoritative = await read();

  for (const delayMs of retryDelaysMs) {
    const mismatches = threadSettingsReadbackMismatches(requested, authoritative);
    if (mismatches.length === 0) {
      return { authoritative, mismatches };
    }

    await wait(delayMs);
    authoritative = await read();
  }

  return {
    authoritative,
    mismatches: threadSettingsReadbackMismatches(requested, authoritative),
  };
}

export function rejectedApprovalReviewerId(
  requested: ThreadSettingsInput,
  authoritative: ThreadDetail,
): string | undefined {
  const requestedReviewer = normalizedSetting(requested.approvalsReviewer);
  if (
    !requestedReviewer ||
    requestedReviewer === normalizedSetting(authoritative.approvalsReviewer)
  ) {
    return undefined;
  }
  return requestedReviewer;
}
