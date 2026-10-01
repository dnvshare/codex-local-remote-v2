# V2 安装提示词

把下面内容连同仓库目录交给本机 AI：

```text
在这台 Windows 电脑上安装或升级 Codex Local Remote V2。

先阅读 AGENTS.md、README-V2.md、docs/quickstart.md、
docs/ai-maintenance.md 和 docs/windows-install.md。修改前只读检查当前 Codex
Desktop 包、随附 Node/Codex、V2 DataDir、28790/28791/28792、计划任务、
Broker、app-server、Sidecar、活动运行代和实际网络入口。

此仓库只包含 V2 控制路径。只使用 scripts/windows-v2 和当前 Desktop 随附运行时；
不要用独立 Codex CLI 冒充 Desktop 同步，不要持久化
CODEX_APP_SERVER_WS_URL，不要暴露 Broker 或 app-server，不要打印或提交密码、
Cookie、token、真实主机名、私人路径或对话内容。

普通 Desktop 启动、Codex 更新、Windows 登录/重启和睡眠恢复必须保持原生。
Deploy/Prepare 可以构建和登记；启动菜单 1/2 的 `Start` 会执行完整部署与一次
明确的 Desktop 冷交接，Open/Close/Status 不得构建。Web/Sidecar 兼容更新优先
使用菜单 3 快速应用；菜单 2 只用于临时 `insecure-http` 排查，公网 HTTPS 应保持
`remote-settings.json` 的 `https` 并使用菜单 1。
不要从会被 Desktop 关闭的 AI 任务中执行最终 Open/Close 验收，生成根目录 CMD
入口并让我执行。

进程清理只能依据 V2 receipt 的 PID 与启动时间；遇到未知进程或端口占用时失败
关闭。state.json 必须跨进程串行、锁内重读并原子替换。运行定向检查并区分
静态检查、自动化测试、真实 Desktop 验收和公网 HTTPS 验收。

网络入口可选择局域网、IIS/NPS、Caddy 或可选 Funnel。公网必须使用 HTTPS，
NPS 内部端口不得直接公开。只有需要我输入密码、选择项目、批准公网暴露或执行
最终 Desktop 冷交接时才停下来。
```
