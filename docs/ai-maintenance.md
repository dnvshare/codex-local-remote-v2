# V2 AI 安装与维护边界

## 开始前

AI 必须先读取 `AGENTS.md`、`README-V2.md`、`docs/quickstart.md` 和
`docs/windows-install.md`，再只读检查：

- Codex Desktop 包及随附 Node/Codex；
- `%LOCALAPPDATA%\CodexLocalRemoteV2`；
- `28790/28791/28792` 监听器；
- `Codex Local Remote V2` 按需计划任务；
- Desktop、Broker、app-server、Sidecar 与当前运行代；
- 用户实际采用的局域网、IIS/NPS 或 Funnel 入口。

不得输出密码、Cookie、token、能力 URL、提示词、对话正文或私人文件内容。

## 生命周期

- 此仓库只维护 V2，不引入旧版控制路径或第二套 owner。
- 只使用 `scripts/windows-v2`。
- `Deploy/Prepare` 可以构建和登记；菜单 1/2 的 `Start` 会执行完整部署与一次
  强制冷交接；`Open/Close/Status` 不得构建或选择源码。
- AI 不得执行会终止当前任务宿主的 Open/Close 验收；最终冷启动由用户从根目录
  CMD 菜单执行。
- V2 不热接管原生 Desktop。完整启动需要一次明确授权的冷交接。
- Web/Sidecar 兼容更新使用菜单选项 3，不重启 Broker、app-server 或 Desktop。
- 菜单 2 只临时使用 `insecure-http` 进行本机或受信任局域网排查；公网 HTTPS
  始终使用 `remote-settings.json` 的 `https` 和菜单选项 1。
- 菜单 4 只准备运行代，菜单 5 只读查看状态，菜单 7 关闭 V2 但不重启
  Desktop，菜单 8 查看切换日志。
- 普通 Desktop 启动、Codex 更新、Windows 登录/重启和睡眠恢复始终原生。

## 安全边界

- Sidecar 可按配置绑定 LAN；Broker `28791` 和 app-server `28792` 必须只绑定
  回环地址。
- `insecure-http` 不关闭认证、同源、CSRF、限速或幂等校验，但不能作为公网
  明文入口。
- 公网必须通过 HTTPS 代理；NPS 内部端口不得直接暴露公网。
- 不得持久化 `CODEX_APP_SERVER_WS_URL`，不得用独立 Codex CLI 创建第二 owner。
- 进程清理必须依据 V2 receipt 的 PID 与启动时间；未知进程或端口占用失败关闭，
  不得按进程名称批量终止。
- `state.json` 修改必须经过跨进程锁、锁内重读和原子替换。

## 修改与验证

修改前比较源码 payload hash、`current-release.json` 和活动运行代；不能把脚本的
“复用”输出当成部署成功证明。

默认验证：

```powershell
pnpm check
```

若本机没有符合要求的 pnpm，必须报告工具链缺失，并使用 Desktop 随附 Node
运行可以独立执行的 typecheck、Vitest、ESLint、Prettier 和 public-safety 检查；
不得把部分检查说成完整通过。

共享 owner 的完成声明需要真实机器证明：Desktop 与 Sidecar 连接同一 Broker，
注册项目与无项目任务的 thread/turn 一致，实时事件和审批一致，Desktop 缺失时
失败关闭。

公网完成声明还需要 TLS、页面、登录 Cookie、CSRF、实时事件、PWA manifest 和
Service Worker 验证。TCP 通或 HTTP 页面可打开都不等于 HTTPS 部署完成。
