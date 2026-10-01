import { useState, type ReactNode } from "react";
import type {
  ApprovalRequest,
  CollaborationModeOption,
  ConversationItem,
  ModelOption,
  QueuedTurnItem,
  ReasoningEffort,
  ThreadGoal,
  ThreadGoalStatus,
} from "@codex-local-remote/contracts";
import { Button, Icon, Sheet, type IconName } from "@codex-local-remote/ui";
import {
  composerToolActions,
  CODEX_DEFAULT_SERVICE_TIER,
  collaborationModeDisplayLabel,
  modelComposerLabel,
  serviceTierChoices,
  serviceTierOptions,
  type ComposerCapabilities,
  type ServiceTierChoice,
} from "./composer-product";
import { normalizeReasoningEffortForModel } from "./model-effort";
import { currentUiLocale, uiText } from "./locale";

const effortLabels: Readonly<Record<string, string>> = {
  none: "无",
  minimal: "极简",
  low: "低",
  medium: "中",
  high: "高",
  max: "最高",
  xhigh: "极高",
  ultra: "ultra",
};

export function reasoningEffortLabel(effort: ReasoningEffort | undefined): string {
  if (effort === undefined) return uiText("由 Codex 决定", "Codex decides");
  if (currentUiLocale() === "en") {
    const labels: Readonly<Record<string, string>> = {
      none: "None",
      minimal: "Minimal",
      low: "Low",
      medium: "Medium",
      high: "High",
      max: "Maximum",
      xhigh: "Very high",
      ultra: "Ultra",
    };
    return labels[effort] ?? effort;
  }
  return effortLabels[effort] ?? effort;
}

export type ComposerDestination = "steer" | "queue";

export function defaultComposerDestination(queueSupported: boolean): ComposerDestination {
  return queueSupported ? "queue" : "steer";
}

export function ComposerContextRows({
  controls,
  goal,
}: {
  controls?: ReactNode;
  goal?: ReactNode;
}) {
  if (!controls && !goal) return null;
  return (
    <div className="composer__context">
      {goal ? <div className="composer__goal-row">{goal}</div> : null}
      {controls ? <div className="composer__context-bar">{controls}</div> : null}
    </div>
  );
}

function goalStatusLabel(status: ThreadGoalStatus): string {
  const labels: Readonly<Record<ThreadGoalStatus, readonly [string, string]>> = {
    active: ["进行中", "Active"],
    paused: ["已暂停", "Paused"],
    blocked: ["受阻", "Blocked"],
    usageLimited: ["用量受限", "Usage limited"],
    budgetLimited: ["预算受限", "Budget limited"],
    complete: ["已完成", "Completed"],
  };
  const [zh, en] = labels[status];
  return uiText(zh, en);
}

export function GoalInlineControl({
  busy,
  goal,
  onClear,
  onOpen,
  onStatusChange,
}: {
  busy: boolean;
  goal: ThreadGoal;
  onClear: () => void;
  onOpen: () => void;
  onStatusChange: (status: "active" | "paused") => void;
}) {
  if (goal.status === "complete") return null;
  const active = goal.status === "active";
  const paused = goal.status === "paused";
  const statusAction = active
    ? uiText("暂停", "Pause")
    : paused
      ? uiText("继续", "Resume")
      : uiText("开始", "Start");
  return (
    <div className="composer-goal" data-testid="composer-goal">
      <button
        aria-label={`${uiText("编辑任务目标", "Edit task goal")}: ${goal.objective}`}
        className="composer-goal__summary"
        data-testid="composer-goal-open"
        onClick={onOpen}
        type="button"
      >
        <Icon name="target" size={16} />
        <span>
          <small>{goalStatusLabel(goal.status)}</small>
          <strong>{goal.objective}</strong>
        </span>
      </button>
      <div className="composer-goal__actions">
        <button
          aria-label={`${statusAction} ${uiText("任务目标", "task goal")}`}
          disabled={busy}
          onClick={() => onStatusChange(active ? "paused" : "active")}
          type="button"
        >
          {statusAction}
        </button>
        <button
          aria-label={uiText("删除任务目标", "Delete task goal")}
          disabled={busy}
          onClick={onClear}
          type="button"
        >
          {uiText("删除", "Delete")}
        </button>
      </div>
    </div>
  );
}

export function DeliveryModeSwitch({
  mode,
  queueSupported,
  onChange,
}: {
  mode: ComposerDestination;
  queueSupported: boolean;
  onChange: (mode: ComposerDestination) => void;
}) {
  return (
    <div className="delivery-switch" data-testid="delivery-mode">
      <span className="delivery-switch__label">{uiText("发送到", "Send to")}</span>
      <button
        aria-pressed={mode === "steer"}
        data-testid="delivery-steer"
        onClick={() => onChange("steer")}
        type="button"
        title={uiText(
          "立即发送到当前回复，不等待本轮结束",
          "Send to the current reply without waiting for this turn to finish",
        )}
      >
        <span className="delivery-switch__full-label">{uiText("当前回复", "Current reply")}</span>
        <span className="delivery-switch__compact-label">{uiText("当前", "Now")}</span>
      </button>
      {queueSupported ? (
        <button
          aria-pressed={mode === "queue"}
          data-testid="delivery-queue"
          onClick={() => onChange("queue")}
          type="button"
          title={uiText("等待当前回复结束后再发送", "Send after the current reply finishes")}
        >
          {uiText("排队", "Queue")}
        </button>
      ) : null}
    </div>
  );
}

export function PlanProgressControl({
  plan,
}: {
  plan: Extract<ConversationItem, { kind: "plan-progress" }>;
}) {
  const [open, setOpen] = useState(false);
  const firstUnfinishedStep = plan.steps.findIndex((step) => step.status !== "completed");
  const currentStep = firstUnfinishedStep >= 0 ? firstUnfinishedStep + 1 : plan.steps.length;
  const completedSteps = plan.steps.filter((step) => step.status === "completed").length;

  return (
    <details
      className="composer-plan-progress"
      data-testid="composer-plan-progress"
      onToggle={(event) => setOpen(event.currentTarget.open)}
      open={open}
    >
      <summary
        aria-label={`${uiText("查看计划进度", "View plan progress")}, ${uiText(`第 ${currentStep}/${plan.steps.length} 步`, `Step ${currentStep}/${plan.steps.length}`)}`}
      >
        <span className="composer-plan-progress__ring" aria-hidden="true">
          {currentStep}
        </span>
        <strong>
          {uiText(
            `第 ${currentStep}/${plan.steps.length} 步`,
            `Step ${currentStep}/${plan.steps.length}`,
          )}
        </strong>
        <Icon name="chevron-down" size={14} />
      </summary>
      <div className="composer-plan-progress__popover">
        <header>
          <span>
            <strong>{uiText("任务进度", "Task progress")}</strong>
            <small>
              {completedSteps}/{plan.steps.length} {uiText("步已完成", "steps complete")}
            </small>
          </span>
          <button
            aria-label={uiText("关闭任务进度", "Close task progress")}
            data-testid="composer-plan-progress-close"
            onClick={() => setOpen(false)}
            type="button"
          >
            <Icon name="close" size={15} />
          </button>
        </header>
        {plan.explanation ? <p>{plan.explanation}</p> : null}
        <ol>
          {plan.steps.map((step, index) => (
            <li
              className={`composer-plan-progress__step composer-plan-progress__step--${step.status}`}
              key={`${index}-${step.text}`}
            >
              <span aria-hidden="true">
                <Icon
                  name={
                    step.status === "completed"
                      ? "check"
                      : step.status === "inProgress"
                        ? "activity"
                        : "clock"
                  }
                  size={14}
                />
              </span>
              <span>
                <small>{uiText(`第 ${index + 1} 步`, `Step ${index + 1}`)}</small>
                {step.text}
              </span>
            </li>
          ))}
        </ol>
      </div>
    </details>
  );
}

function selectedTier(
  model: ModelOption | undefined,
  serviceTier: string | null | undefined,
): ServiceTierChoice {
  if (serviceTier === null || serviceTier === undefined) {
    return CODEX_DEFAULT_SERVICE_TIER;
  }
  return (
    serviceTierOptions(model).find((option) => option.id === serviceTier) ??
    CODEX_DEFAULT_SERVICE_TIER
  );
}

export function ComposerSettingsButton({
  disabled,
  effort,
  model,
  models,
  onEffort,
  onModel,
  onOpen,
  serviceTier,
  serviceTiersSupported,
}: {
  disabled?: boolean;
  effort: ReasoningEffort | undefined;
  model: string;
  models: ModelOption[];
  onEffort: (effort: ReasoningEffort | undefined) => void;
  onModel: (model: string) => void;
  onOpen: () => void;
  serviceTier?: string | null;
  serviceTiersSupported: boolean;
}) {
  const selected = models.find((option) => option.id === model);
  const displayedEffort = selected ? normalizeReasoningEffortForModel(selected, effort) : effort;
  const tier = serviceTiersSupported ? selectedTier(selected, serviceTier) : undefined;
  const fastTier =
    tier !== undefined && `${tier.id ?? ""} ${tier.label}`.toLocaleLowerCase().includes("fast");
  const detailedLabel = [
    selected ? modelComposerLabel(selected.displayName) : model,
    reasoningEffortLabel(displayedEffort),
    tier?.label,
  ]
    .filter(Boolean)
    .join(" · ");
  const primaryLabel = selected ? modelComposerLabel(selected.displayName) : model;
  const secondaryLabel = [
    reasoningEffortLabel(displayedEffort),
    tier ? (tier.id === null ? uiText("标准", "Standard") : tier.label) : undefined,
  ]
    .filter(Boolean)
    .join(" · ");
  return (
    <div className="composer-settings-control">
      <button
        aria-label={uiText(
          `模型与运行设置：${detailedLabel}`,
          `Model and runtime settings: ${detailedLabel}`,
        )}
        className="composer-settings-button"
        data-testid="composer-settings-open"
        disabled={disabled}
        onClick={onOpen}
        type="button"
      >
        {fastTier ? (
          <span
            aria-label={uiText("Fast 加速已开启", "Fast acceleration enabled")}
            className="composer-fast-indicator"
            title="Fast"
          >
            ⚡
          </span>
        ) : null}
        <span className="composer-settings-button__label">
          <span className="composer-settings-button__model">
            {primaryLabel || uiText("选择模型与思考等级", "Choose a model and reasoning level")}
          </span>
          {secondaryLabel ? (
            <span className="composer-settings-button__secondary"> · {secondaryLabel}</span>
          ) : null}
        </span>
        <Icon name="chevron-down" size={14} />
      </button>
      <select
        aria-hidden="true"
        className="composer-compat-select composer-compat-select--model"
        data-testid="next-turn-model"
        onChange={(event) => onModel(event.target.value)}
        tabIndex={-1}
        value={model}
      >
        {!selected && model ? <option value={model}>{model}</option> : null}
        {models.map((option) => (
          <option key={option.id} value={option.id}>
            {option.displayName}
          </option>
        ))}
      </select>
      {selected?.supportedReasoningEfforts.length ? (
        <select
          aria-hidden="true"
          className="composer-compat-select composer-compat-select--effort"
          data-testid="next-turn-effort"
          onChange={(event) => onEffort(event.target.value)}
          tabIndex={-1}
          value={displayedEffort}
        >
          {selected.supportedReasoningEfforts.map((option) => (
            <option key={option} value={option}>
              {reasoningEffortLabel(option)}
            </option>
          ))}
        </select>
      ) : null}
    </div>
  );
}

function OptionButton({
  active,
  description,
  disabled,
  label,
  onClick,
}: {
  active: boolean;
  description?: string;
  disabled?: boolean;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      aria-pressed={active}
      className={`composer-option ${active ? "is-selected" : ""}`}
      disabled={disabled}
      onClick={onClick}
      type="button"
    >
      <span>
        <strong>{label}</strong>
        {description ? <small>{description}</small> : null}
      </span>
      {active ? <Icon name="check" size={17} /> : null}
    </button>
  );
}

export function ComposerSettingsSheet({
  busy,
  demo = false,
  effort,
  model,
  models,
  onApply,
  onClose,
  onEffort,
  onModel,
  onServiceTier,
  open,
  serviceTier,
  serviceTiersSupported,
}: {
  busy: boolean;
  demo?: boolean;
  effort: ReasoningEffort | undefined;
  model: string;
  models: ModelOption[];
  onApply: () => void;
  onClose: () => void;
  onEffort: (effort: ReasoningEffort | undefined) => void;
  onModel: (model: string) => void;
  onServiceTier: (tier: string | null) => void;
  open: boolean;
  serviceTier?: string | null;
  serviceTiersSupported: boolean;
}) {
  const selected = models.find((option) => option.id === model);
  const normalizedEffort = selected ? normalizeReasoningEffortForModel(selected, effort) : effort;
  const tiers = serviceTiersSupported ? serviceTierChoices(selected) : [];
  const currentTier = selectedTier(selected, serviceTier);
  return (
    <Sheet
      description={uiText("运行中的回复不会变更。", "The running reply will not be changed.")}
      footer={
        <Button disabled={busy} onClick={onApply} variant="primary">
          {busy ? uiText("正在保存…", "Saving…") : uiText("保存设置", "Save settings")}
        </Button>
      }
      onClose={onClose}
      open={open}
      title={uiText("模型与运行设置", "Model and runtime settings")}
    >
      <div className="composer-sheet-section">
        <h3>{uiText("模型", "Model")}</h3>
        {demo ? (
          <p
            className="composer-sheet-note composer-sheet-note--demo"
            data-testid="demo-model-note"
          >
            {uiText(
              "当前是演示模式，下面只用于展示交互。正式连接会实时显示 Codex Desktop 当前提供的全部模型，并且只显示所选模型真实支持的速度档。",
              "Demo mode is active; the controls below only demonstrate the interaction. A live connection shows all models provided by Codex Desktop and only the speed tiers actually supported by the selected model.",
            )}
          </p>
        ) : null}
        {!selected && model ? (
          <p className="composer-sheet-note" data-testid="runtime-model-outside-catalog">
            {uiText("当前实际模型", "Current model")}: {model}.{" "}
            {uiText(
              "它不在 Codex 当前可选目录中；选择下方模型并保存后生效。",
              "It is not in the current Codex catalog; choose a model below and save to apply it.",
            )}
          </p>
        ) : null}
        <div className="composer-option-list">
          {models.map((option) => (
            <OptionButton
              active={option.id === selected?.id}
              {...(option.description ? { description: option.description } : {})}
              key={option.id}
              label={option.displayName}
              onClick={() => onModel(option.id)}
            />
          ))}
        </div>
      </div>
      <div className="composer-sheet-section">
        <h3>{uiText("思考等级", "Reasoning level")}</h3>
        {selected?.supportedReasoningEfforts.length ? (
          <div className="composer-choice-row">
            {selected.supportedReasoningEfforts.map((option) => (
              <button
                aria-pressed={option === normalizedEffort}
                className={option === normalizedEffort ? "is-selected" : ""}
                key={option}
                onClick={() => onEffort(option)}
                type="button"
              >
                {reasoningEffortLabel(option)}
              </button>
            ))}
          </div>
        ) : (
          <p className="composer-sheet-note">
            {effort
              ? `${uiText("当前实际思考等级", "Current reasoning level")}: ${reasoningEffortLabel(effort)}; ${uiText("Codex 未公开这个模型的可选等级。", "Codex did not expose selectable levels for this model.")}`
              : uiText(
                  "当前模型未公开可选思考等级，将由 Codex 决定。",
                  "This model does not expose selectable reasoning levels; Codex will decide.",
                )}
          </p>
        )}
      </div>
      {tiers.length ? (
        <div className="composer-sheet-section">
          <h3>{uiText("速度", "Speed")}</h3>
          <div className="composer-option-list composer-option-list--compact">
            {tiers.map((tier) => (
              <OptionButton
                active={tier.id === currentTier?.id}
                {...(tier.description ? { description: tier.description } : {})}
                key={tier.id ?? "codex-default"}
                label={tier.label}
                onClick={() => onServiceTier(tier.id)}
              />
            ))}
          </div>
        </div>
      ) : null}
    </Sheet>
  );
}

const toolIcons: Record<"attach" | "goal" | "plan" | "compact", IconName> = {
  attach: "paperclip",
  goal: "target",
  plan: "layers",
  compact: "spark",
};

export function ComposerToolsSheet({
  canAttach,
  canCompact,
  capabilities,
  collaborationModes,
  onClose,
  onAttach,
  onCompact,
  onGoal,
  onPlan,
  open,
}: {
  canAttach: boolean;
  canCompact: boolean;
  capabilities: ComposerCapabilities | undefined;
  collaborationModes: CollaborationModeOption[];
  onClose: () => void;
  onAttach: () => void;
  onCompact: () => void;
  onGoal: () => void;
  onPlan: () => void;
  open: boolean;
}) {
  const actions = composerToolActions({
    capabilities,
    canAttach,
    canCompact,
    hasCollaborationModes: collaborationModes.some((mode) => mode.available),
  });
  return (
    <Sheet
      description={uiText(
        "这里只显示当前 Codex 运行时确认支持的操作。",
        "Only operations confirmed by the current Codex runtime are shown here.",
      )}
      onClose={onClose}
      open={open}
      title={uiText("对话工具", "Conversation tools")}
    >
      {actions.length ? (
        <div className="composer-tools-list">
          {actions.map((action) => (
            <button
              disabled={action.disabled}
              key={action.id}
              onClick={() => {
                if (action.id === "attach") onAttach();
                if (action.id === "goal") onGoal();
                if (action.id === "plan") onPlan();
                if (action.id === "compact") onCompact();
              }}
              type="button"
            >
              <span className="composer-tools-list__icon">
                <Icon name={toolIcons[action.id]} size={19} />
              </span>
              <span>
                <strong>{action.label}</strong>
                <small>{action.description}</small>
              </span>
              <Icon name="chevron-right" size={17} />
            </button>
          ))}
        </div>
      ) : (
        <p className="composer-sheet-empty">
          {uiText(
            "当前运行时没有可用的附加工具。",
            "No additional tools are available in the current runtime.",
          )}
        </p>
      )}
    </Sheet>
  );
}

export function GoalSheet({
  busy,
  hasGoal,
  onChange,
  onClear,
  onClose,
  onSave,
  onStatusChange,
  open,
  status,
  value,
}: {
  busy: boolean;
  hasGoal: boolean;
  onChange: (value: string) => void;
  onClear: () => void;
  onClose: () => void;
  onSave: () => void;
  onStatusChange: (status: "active" | "paused") => void;
  open: boolean;
  status?: ThreadGoalStatus;
  value: string;
}) {
  return (
    <Sheet
      description={uiText(
        "目标会随这个对话保存；要立刻改变当前回复，请同时发送一条引导。",
        "The goal is saved with this conversation; send guidance as well if you want to change the current reply immediately.",
      )}
      footer={
        <>
          <Button disabled={busy || !value.trim()} onClick={onSave} variant="primary">
            {hasGoal ? uiText("保存修改", "Save changes") : uiText("保存目标", "Save goal")}
          </Button>
          {hasGoal ? (
            <Button
              disabled={busy}
              onClick={() => onStatusChange(status === "active" ? "paused" : "active")}
              variant="ghost"
            >
              {status === "active"
                ? uiText("暂停目标", "Pause goal")
                : status === "paused"
                  ? uiText("继续目标", "Resume goal")
                  : uiText("开始目标", "Start goal")}
            </Button>
          ) : null}
          {hasGoal ? (
            <Button disabled={busy} onClick={onClear} variant="ghost">
              {uiText("删除目标", "Delete goal")}
            </Button>
          ) : null}
        </>
      }
      onClose={onClose}
      open={open}
      title={uiText("任务目标", "Task goal")}
    >
      <label className="goal-editor">
        <span>{uiText("持续目标", "Ongoing goal")}</span>
        <textarea
          maxLength={2_000}
          onChange={(event) => onChange(event.target.value)}
          placeholder={uiText(
            "例如：完成可发布的实现，并用真实移动端流程验收。",
            "Example: finish a shippable implementation and verify it through a real mobile flow.",
          )}
          rows={5}
          value={value}
        />
      </label>
    </Sheet>
  );
}

export function PlanModeSheet({
  modes,
  onChange,
  onClose,
  open,
  value,
}: {
  modes: CollaborationModeOption[];
  onChange: (id: string) => void;
  onClose: () => void;
  open: boolean;
  value: string;
}) {
  return (
    <Sheet
      description={uiText(
        "为后续工作选择协作方式；当前回复仍可直接引导。",
        "Choose a collaboration mode for future work; the current reply can still be guided directly.",
      )}
      onClose={onClose}
      open={open}
      title={uiText("计划模式", "Plan mode")}
    >
      <div className="composer-option-list">
        {modes.map((mode) => (
          <OptionButton
            active={mode.id === value}
            {...(mode.description ? { description: mode.description } : {})}
            disabled={!mode.available}
            key={mode.id}
            label={collaborationModeDisplayLabel(mode.id, mode.displayName)}
            onClick={() => {
              onChange(mode.id);
              onClose();
            }}
          />
        ))}
      </div>
    </Sheet>
  );
}

export function InlineDecisionStack({
  approvals,
  onOpen,
}: {
  approvals: ApprovalRequest[];
  onOpen: (approval: ApprovalRequest) => void;
}) {
  if (!approvals.length) return null;
  return (
    <section
      aria-label={uiText("当前对话等待处理", "Current conversation needs attention")}
      className="thread-decision-stack"
      data-testid="thread-approval-stack"
    >
      {approvals.map((approval) => (
        <button key={approval.id} onClick={() => onOpen(approval)} type="button">
          <span className="thread-decision-stack__icon">
            <Icon name={approval.questions?.length ? "message" : "shield"} size={18} />
          </span>
          <span>
            <strong>{approval.title}</strong>
            <small>
              {approval.questions?.[0]?.question ??
                approval.explanation ??
                uiText("Codex 正在等待你的决定", "Codex is waiting for your decision")}
            </small>
          </span>
          <span className="thread-decision-stack__action">{uiText("处理", "Review")}</span>
        </button>
      ))}
    </section>
  );
}

export function QueueShelf({
  busyId,
  canSteer = false,
  items,
  running,
  onDelete,
  onDispatch,
  onMove,
  onSteer,
  onUpdate,
}: {
  busyId?: string;
  canSteer?: boolean;
  items: QueuedTurnItem[];
  running: boolean;
  onDelete: (item: QueuedTurnItem) => void;
  onDispatch: (item: QueuedTurnItem) => void;
  onMove: (item: QueuedTurnItem, offset: -1 | 1) => void;
  onSteer?: (item: QueuedTurnItem) => void;
  onUpdate: (item: QueuedTurnItem, prompt: string) => void;
}) {
  const [editingId, setEditingId] = useState("");
  const [editDraft, setEditDraft] = useState("");
  const pendingItems = items.filter((item) => item.state !== "started");
  if (!pendingItems.length) return null;
  return (
    <section className="queue-shelf" data-testid="queue-shelf">
      <header>
        <span>
          <Icon name="clock" size={15} />
          {uiText("消息队列", "Message queue")}
        </span>
        <b>
          {pendingItems.length} {uiText("条", "items")}
        </b>
      </header>
      <div className="queue-shelf__items">
        {pendingItems.map((item, index) => {
          const editing = editingId === item.id;
          const busy = busyId === item.id;
          const dispatching = item.state === "dispatching";
          const recoverable =
            item.state === "queued" || item.state === "paused" || item.state === "ambiguous";
          const dispatchLabel =
            item.state === "ambiguous"
              ? uiText(
                  "确认重试发送结果未知的消息",
                  "Confirm retry for a message with an unknown send result",
                )
              : item.state === "paused"
                ? uiText("重新发送这条消息", "Resend this message")
                : running
                  ? uiText(
                      "当前回复结束后可手动发送",
                      "Send manually after the current reply finishes",
                    )
                  : uiText("立即发送这条消息", "Send this message now");
          return (
            <article className="queue-item" data-testid="queue-item" key={item.id}>
              <span className="queue-item__order">{index + 1}</span>
              <div className="queue-item__body">
                {editing ? (
                  <textarea
                    aria-label={uiText("编辑排队消息", "Edit queued message")}
                    onChange={(event) => setEditDraft(event.target.value)}
                    rows={2}
                    value={editDraft}
                  />
                ) : (
                  <p>
                    {item.prompt ??
                      uiText("这条消息正在由 Codex 处理", "Codex is processing this message")}
                  </p>
                )}
                {item.attachments?.length ? (
                  <small className="queue-item__attachments">
                    <Icon name="paperclip" size={13} />
                    {item.attachments.length} {uiText("个文件或文件夹", "files or folders")}
                  </small>
                ) : null}
                {dispatching ? (
                  <small className="queue-item__status">
                    {uiText(
                      "正在发送，结果确认前暂不可修改或删除",
                      "Sending; editing and deletion are unavailable until the result is confirmed",
                    )}
                  </small>
                ) : null}
                {!dispatching ? (
                  <div className="queue-item__actions">
                    {editing ? (
                      <>
                        <Button
                          disabled={!editDraft.trim() || busy}
                          onClick={() => {
                            onUpdate(item, editDraft.trim());
                            setEditingId("");
                          }}
                          size="compact"
                          variant="primary"
                        >
                          {uiText("保存", "Save")}
                        </Button>
                        <Button onClick={() => setEditingId("")} size="compact" variant="ghost">
                          {uiText("取消", "Cancel")}
                        </Button>
                      </>
                    ) : (
                      <>
                        <Button
                          aria-label={uiText("上移排队消息", "Move queued message up")}
                          disabled={!recoverable || index === 0 || busy}
                          icon="arrow-up"
                          onClick={() => onMove(item, -1)}
                          size="icon"
                          variant="ghost"
                        />
                        <Button
                          aria-label={uiText("下移排队消息", "Move queued message down")}
                          disabled={!recoverable || index === pendingItems.length - 1 || busy}
                          icon="arrow-down"
                          onClick={() => onMove(item, 1)}
                          size="icon"
                          variant="ghost"
                        />
                        <Button
                          aria-label={uiText("编辑排队消息", "Edit queued message")}
                          disabled={!recoverable || !item.prompt || busy}
                          icon="edit"
                          onClick={() => {
                            setEditingId(item.id);
                            setEditDraft(item.prompt ?? "");
                          }}
                          size="icon"
                          variant="ghost"
                        />
                        <Button
                          aria-label={uiText("删除排队消息", "Delete queued message")}
                          disabled={!recoverable || busy}
                          icon="trash"
                          onClick={() => onDelete(item)}
                          size="icon"
                          variant="ghost"
                        />
                        {canSteer && item.state !== "ambiguous" && onSteer ? (
                          <Button
                            aria-label={uiText(
                              "将排队消息改为当前引导",
                              "Turn queued message into current guidance",
                            )}
                            className="queue-item__steer"
                            disabled={!recoverable || busy}
                            icon="target"
                            onClick={() => onSteer(item)}
                            size="compact"
                            variant="secondary"
                          >
                            {uiText("改为引导", "Guide now")}
                          </Button>
                        ) : (
                          <Button
                            aria-label={dispatchLabel}
                            disabled={!recoverable || running || busy}
                            icon="send"
                            onClick={() => onDispatch(item)}
                            size="icon"
                            variant="secondary"
                          />
                        )}
                      </>
                    )}
                  </div>
                ) : null}
              </div>
            </article>
          );
        })}
      </div>
    </section>
  );
}
