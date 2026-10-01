export type UiLocale = "zh" | "en";

const STORAGE_KEY = "codex-local-remote:locale";

export interface UiLocaleCopy {
  text: (zh: string, en: string) => string;
  nav: readonly [string, string, string];
  languageLabel: string;
  languageChoice: string;
  brandSubtitle: string;
  back: string;
  tasks: string;
  files: string;
  settings: string;
  newShort: string;
  newTask: string;
  pinned: string;
  recent: string;
  viewAll: string;
  connected: string;
  history: string;
  unprojected: string;
  computerReady: string;
  tasksWorking: (count: number) => string;
  approvalsWaiting: (count: number) => string;
  sharedTaskList: string;
  runtimeDegraded: string;
  runtimeDegradedBody: string;
  taskPageDescription: string;
  current: string;
  archived: string;
  archiveScopeLabel: string;
  searchTasks: string;
  searchArchivedTasks: string;
  clearSearch: string;
  allTypes: string;
  running: string;
  archivedHistory: string;
  noTasks: string;
  noArchivedTasks: string;
  noMatchingTasks: string;
  noTasksDescription: string;
  noArchivedDescription: string;
  noMatchingDescription: string;
  newConversation: string;
  startNewTask: string;
  startNewTaskDescription: string;
  chooseLocation: string;
  fixedProjectBoundary: string;
  noProject: string;
  noProjectDescription: string;
  projectFiles: string;
  projectFilesDescription: string;
  currentProject: string;
  filterFiles: string;
  settingsAndDiagnostics: string;
  settingsDescription: string;
  connection: string;
  publicEntry: string;
  publicConnected: string;
  liveEvents: string;
  liveConnected: string;
  reconnecting: string;
  healthy: string;
  disconnected: string;
  refreshDiagnostics: string;
}

const copies: Record<UiLocale, UiLocaleCopy> = {
  zh: {
    text: (zh) => zh,
    nav: ["任务", "文件", "设置"],
    languageLabel: "切换界面语言",
    languageChoice: "EN",
    brandSubtitle: "桌面 AI 控制台",
    back: "返回",
    tasks: "任务",
    files: "文件",
    settings: "设置",
    newShort: "新建",
    newTask: "新建任务",
    pinned: "置顶",
    recent: "最近",
    viewAll: "查看全部",
    connected: "已连接到电脑",
    history: "历史记录",
    unprojected: "无项目",
    computerReady: "电脑已就绪",
    tasksWorking: (count) => `${count} 个任务正在工作`,
    approvalsWaiting: (count) => `${count} 项操作等待你的决定`,
    sharedTaskList: "Desktop、浏览器和手机共享同一任务列表",
    runtimeDegraded: "Codex 连接已降级",
    runtimeDegradedBody:
      "检测到运行时更新或兼容性状态无法确认。现有任务仍可查看；新任务暂时停用，避免请求进入未经确认的 Desktop 运行时。",
    taskPageDescription: "运行中、置顶、最近和归档任务都在这里，顺序跟随 Desktop。",
    current: "当前",
    archived: "已归档",
    archiveScopeLabel: "任务归档范围",
    searchTasks: "搜索当前任务",
    searchArchivedTasks: "搜索已归档任务",
    clearSearch: "清空搜索",
    allTypes: "全部类型",
    running: "进行中",
    archivedHistory: "历史记录",
    noTasks: "当前没有任务",
    noArchivedTasks: "还没有归档任务",
    noMatchingTasks: "没有找到任务",
    noTasksDescription: "开始新任务后，它会显示在这里。",
    noArchivedDescription: "归档后的对话会保留在这里，随时可以回来查看。",
    noMatchingDescription: "换一个关键词或筛选条件试试。",
    newConversation: "新建对话",
    startNewTask: "开始新任务",
    startNewTaskDescription: "选择本机项目，或开始一段不关联任何项目的对话。",
    chooseLocation: "选择位置",
    fixedProjectBoundary: "远程端不能添加任意目录",
    noProject: "不关联项目",
    noProjectDescription: "显示在 Desktop 的最近任务中",
    projectFiles: "电脑文件",
    projectFilesDescription: "管理这台电脑上的磁盘与文件。",
    currentProject: "当前项目",
    filterFiles: "筛选",
    settingsAndDiagnostics: "设置与诊断",
    settingsDescription: "查看连接、额度、会话和当前服务能力。",
    connection: "连接",
    publicEntry: "公网入口",
    publicConnected: "HTTP 请求通道正常",
    liveEvents: "实时更新",
    liveConnected: "共享任务实时事件连接正常",
    reconnecting: "正在尝试重新连接",
    healthy: "正常",
    disconnected: "断线",
    refreshDiagnostics: "刷新诊断",
  },
  en: {
    text: (_zh, en) => en,
    nav: ["Tasks", "Files", "Settings"],
    languageLabel: "Switch interface language",
    languageChoice: "中",
    brandSubtitle: "Desktop AI console",
    back: "Back",
    tasks: "Tasks",
    files: "Files",
    settings: "Settings",
    newShort: "New",
    newTask: "New task",
    pinned: "Pinned",
    recent: "Recent",
    viewAll: "View all",
    connected: "Connected to your computer",
    history: "History",
    unprojected: "No project",
    computerReady: "Computer ready",
    tasksWorking: (count) => `${count} ${count === 1 ? "task is" : "tasks are"} running`,
    approvalsWaiting: (count) =>
      `${count} ${count === 1 ? "action needs" : "actions need"} your decision`,
    sharedTaskList: "Desktop, web and mobile share the same task list",
    runtimeDegraded: "Codex connection degraded",
    runtimeDegradedBody:
      "A runtime update or compatibility state could not be confirmed. Existing tasks remain readable; new tasks are paused until the Desktop runtime is verified.",
    taskPageDescription: "Running, pinned, recent and archived tasks, in Desktop order.",
    current: "Current",
    archived: "Archived",
    archiveScopeLabel: "Task archive scope",
    searchTasks: "Search current tasks",
    searchArchivedTasks: "Search archived tasks",
    clearSearch: "Clear search",
    allTypes: "All types",
    running: "Running",
    archivedHistory: "History",
    noTasks: "No current tasks",
    noArchivedTasks: "No archived tasks",
    noMatchingTasks: "No tasks found",
    noTasksDescription: "Your first task will appear here.",
    noArchivedDescription: "Archived tasks stay here when you need them.",
    noMatchingDescription: "Try a different keyword or filter.",
    newConversation: "New conversation",
    startNewTask: "Start a new task",
    startNewTaskDescription: "Choose a local project or start a conversation without a project.",
    chooseLocation: "Choose location",
    fixedProjectBoundary: "Remote access cannot add arbitrary folders",
    noProject: "No project",
    noProjectDescription: "Appears in Desktop recent tasks",
    projectFiles: "Computer files",
    projectFilesDescription: "Manage drives and files available to the current Windows identity.",
    currentProject: "Current project",
    filterFiles: "Filter",
    settingsAndDiagnostics: "Settings & diagnostics",
    settingsDescription: "Review connection, usage, session and current service capabilities.",
    connection: "Connection",
    publicEntry: "Public access",
    publicConnected: "HTTP request path is available",
    liveEvents: "Live updates",
    liveConnected: "Shared task events are connected",
    reconnecting: "Trying to reconnect",
    healthy: "Healthy",
    disconnected: "Disconnected",
    refreshDiagnostics: "Refresh diagnostics",
  },
};

export function localeCopy(locale: UiLocale): UiLocaleCopy {
  return copies[locale];
}

export function readUiLocale(storage: Pick<Storage, "getItem">): UiLocale {
  try {
    return storage.getItem(STORAGE_KEY) === "en" ? "en" : "zh";
  } catch {
    return "zh";
  }
}

export function writeUiLocale(storage: Pick<Storage, "setItem">, locale: UiLocale): void {
  try {
    storage.setItem(STORAGE_KEY, locale);
  } catch {
    // Language persistence is best effort and must never block the control surface.
  }
}

export function currentUiLocale(): UiLocale {
  if (
    typeof document !== "undefined" &&
    document.documentElement?.lang.toLowerCase().startsWith("en")
  ) {
    return "en";
  }
  if (typeof localStorage !== "undefined" && readUiLocale(localStorage) === "en") return "en";
  return "zh";
}

export function uiText(zh: string, en: string): string {
  return currentUiLocale() === "en" ? en : zh;
}

const serviceMessageCopies: Readonly<Record<string, string>> = {
  "This conversation has no project directory available for registration":
    "此会话没有可用于登记的项目目录，请检查电脑端工作目录。",
  "This conversation's project is not registered on the local computer; the next turn cannot start":
    "此会话的项目尚未在运行 Remote 的电脑上登记，暂时不能开始下一轮。",
  "The shared Broker has not confirmed a healthy connection between Codex Desktop and the remote client; existing content remains readable and new tasks are paused.":
    "共享 Broker 尚未确认 Codex Desktop 与远程端处于同一健康连接；现有内容仍可查看，新任务已暂停。",
  "The shared Broker is restoring some historical tasks in the background; operations may continue when the live model and task probes pass.":
    "共享 Broker 正在后台恢复部分历史任务；实时模型与任务探针通过时仍可继续操作。",
  "The live connection between the shared Broker and Codex Desktop could not be verified; remote control is degraded and new tasks are paused.":
    "无法验证共享 Broker 与 Codex Desktop 的实时连接，远程控制已降级，新任务已暂停。",
  "The Codex Desktop startup health receipt is missing; remote control is marked degraded.":
    "Codex Desktop 启动健康回执缺失，远程控制已标记为降级。",
  "Codex Desktop was updated; continue when the live capability probe passes, and update the managed connection after the current work ends to use the new runtime.":
    "Codex Desktop 已更新；当前实时能力探针通过时可继续使用，待当前工作结束后热更新受管连接以采用新运行时。",
  "Codex Desktop update compatibility could not be confirmed; existing tasks were not interrupted and remote control is marked degraded.":
    "无法确认 Codex Desktop 更新兼容性；现有任务未被中断，远程控制已标记为降级。",
  "The managed Codex Desktop connection is starting; remote control is temporarily unavailable.":
    "Codex Desktop 受管连接正在启动，远程控制暂不可用。",
  "Codex Desktop startup health is degraded; existing tasks were not interrupted and remote control is marked degraded.":
    "Codex Desktop 启动健康状态已降级；现有任务未被中断，远程控制已标记为降级。",
  "The Codex Desktop startup health receipt is invalid; remote control is marked degraded.":
    "Codex Desktop 启动健康回执无效，远程控制已标记为降级。",
  "The shared Codex backend is not connected; the remote endpoint will not start a fallback backend to avoid duplicate execution.":
    "共享 Codex 后台尚未连接；为避免双重执行，远程端不会另起备用后台。",
  "There are many historical conversations; load earlier records from the conversation page.":
    "历史对话较多，可在对话页继续加载更早记录。",
};

export function serviceMessageForDisplay(message: string): string {
  return currentUiLocale() === "en" ? message : (serviceMessageCopies[message] ?? message);
}
