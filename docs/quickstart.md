# V2 快速使用指南

## 运行边界

V2 使用一个共享的 Codex app-server：Codex Desktop 与 Sidecar 同时连接只监听
回环地址的 Broker。V2 不热接管已经原生启动的 Desktop；首次启用或完整切换时，
必须从启动菜单执行一次明确的受控重启。

默认端口：

- Sidecar：`0.0.0.0:28790`（`lan`）或 `127.0.0.1:28790`（`localhost`）；
- Broker：`127.0.0.1:28791`；
- app-server：`127.0.0.1:28792`。

Broker 和 app-server 永远不得暴露到局域网或公网。

## 第一次启动

从管理员 CMD 在仓库根目录运行：

```cmd
Start-CodexLocalRemoteV2-OneClick.cmd
```

This opens the Chinese menu. Use `Start-CodexLocalRemoteV2-OneClick-EN.cmd` for
the equivalent English menu. The Web UI and independent mobile setup shell can
switch between Simplified Chinese and English; backend and service diagnostics
remain English.

常用菜单：

1. 强制重启 V2（使用 `remote-settings.json`）；
2. 强制重启 V2（临时使用 HTTP，其余选项使用 `remote-settings.json`）；
3. 只快速应用 Web / Sidecar，不重启 Desktop；
4. 只构建、封存和登记运行代，不启动 Remote；
5. 查看状态；
6. 关闭 V2，并恢复原生 Desktop。
7. 关闭 V2，但不重启 Codex Desktop；
8. 查看最近一次切换日志；

- `0`. 退出菜单。

选项 1 和 2 会执行一次明确的 Desktop 所有权交接。选项 3 只适用于 Broker 和
控制脚本没有变化的 Web/Sidecar 更新；兼容门不通过时会失败，不会擅自重启
Desktop。选项 2 只在本次启动中临时使用 `insecure-http`，其他设置仍来自
`remote-settings.json`。

选项 6 会关闭 V2 并恢复原生 Desktop；选项 7 只关闭 V2，不启动原生 Desktop。

## 统一配置

统一配置文件位于：

```text
%LOCALAPPDATA%\CodexLocalRemoteV2\remote-settings.json
```

首次登记时会自动创建。可以直接编辑以下选项：

- `ListenMode`: `lan` 或 `localhost`；
- `SecurityMode`: `https` 或 `insecure-http`；
- `SidecarPort`、`BrokerPort`、`UpstreamPort`：三者必须不同；
- `BasePath`：默认 `/codex-remote`；
- `AllowedOrigins`：可选的完整来源列表，例如 `https://remote.example.test:2342`；
- `TrustedProxyAddresses`、`TrustedProxyNetworks`：反向代理地址或网段；
- `Auth`：密码最小长度、会话时限和登录限流参数。

修改认证、来源、代理和桌面同步后选择菜单 3 快速应用，只重启 Sidecar，不重启
Codex Desktop。修改监听地址、端口、路径或安全模式后选择菜单 1 完整启动，确保
所有组件使用同一份配置。`insecure-http` 仍保留密码、同源、CSRF、限流和幂等校验，
只是允许 HTTP Cookie。

## 密码与项目

密码只从本机交互输入读取，不要放进参数、环境变量、截图或仓库。可以从已登录的
网页文件选择器登记项目，也可以在管理员 CMD 中使用：

```cmd
scripts\windows-v2\Setup-CodexLocalRemoteV2Password.cmd

scripts\windows-v2\Register-CodexLocalRemoteV2Project.cmd -Id my-project -Name "我的项目" -Root "C:\Projects\my-project"
```

状态文件使用跨进程锁和原子替换；运行中的 Sidecar 在读取项目列表时会重新加载
外部登记结果。更换密码会主动清除已有浏览器会话，需要重新登录。

## 本机与局域网

当 `SecurityMode` 为 `insecure-http` 时，默认 `lan` 地址为：

```text
http://电脑局域网地址:28790/codex-remote/
```

`insecure-http` 只用于受信任局域网诊断。它不会关闭密码、同源、CSRF、限速或
幂等校验，但网络流量仍是明文，不适合作为公网入口。`SecurityMode` 为 `https`
时，Sidecar 内部仍监听 HTTP；浏览器必须通过 HTTPS 反向代理访问，直接使用
`http://` 会被提示改用 HTTPS。

## 公网 HTTPS

公网必须由 IIS、Caddy、Nginx 或 Tailscale Funnel 终止 TLS，再反向代理到
Sidecar。推荐链路：

```text
浏览器 HTTPS
  -> IIS/Caddy 公网端口
  -> 服务器本机的 NPS TCP 入口
  -> NPC 隧道
  -> 本机 127.0.0.1:28790
```

NPS 内部入口与 IIS HTTPS 监听端口必须不同。NPS 端口应通过服务器防火墙禁止
公网直连，只允许反向代理在服务器本机访问。HTTPS 代理必须保留 Host，并设置：

```text
X-Forwarded-Proto: https
X-Forwarded-Host: 原始 Host
```

公网 HTTPS 部署时，让 `remote-settings.json` 保持 `https` 并使用菜单选项 1；菜单
选项 2 仅用于临时 HTTP 调试，不是 HTTPS 启动选项。完整 IIS/NPS 配置见
[Windows 安装与公网入口](windows-install.md)。Tailscale 是可选入口，不是 V2
本地运行或 IIS/NPS 部署的必需依赖。

## 更新

- 仅 Web/Sidecar 变化：使用菜单选项 3；
- Broker、app-server 适配、控制脚本或监听/安全设置变化：使用菜单选项 1；
- 需要临时 HTTP 排查：使用菜单选项 2；
- 只准备运行代、不改变活动进程：使用菜单选项 4；
- 只看状态或最近切换输出：使用菜单选项 5 或 8；
- 关闭 V2 但不重启原生 Desktop：使用菜单选项 7。

源码构建使用 Node.js 24+ 与 pnpm 11。活动运行时必须继续使用当前 Codex
Desktop 随附的 Node 和 Codex，不要安装独立 Codex CLI 冒充 Desktop 同步。

## 状态检查

菜单选项 5 或固定 dispatcher 的 `Status` 都是只读操作：

```powershell
$dispatcher = Join-Path $env:LOCALAPPDATA `
  'CodexLocalRemoteV2\control\CodexLocalRemoteV2.Dispatcher.ps1'
& (Get-Command pwsh.exe).Source -NoLogo -NoProfile -NonInteractive `
  -File $dispatcher -Operation Status `
  -DataDir (Join-Path $env:LOCALAPPDATA 'CodexLocalRemoteV2')
```

健康状态应同时显示 `Phase=ready`、`DesktopConnected=True`、
`SidecarConnected=True` 和 `WebReady=True`。
