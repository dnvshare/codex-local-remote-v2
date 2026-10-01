# Windows V2 安装与公网入口

## 前置条件

- Windows 11；
- 已登录的 Codex Desktop；
- 管理员 CMD 或 PowerShell，用于登记按需计划任务；
- 源码构建需要 Node.js 24+、pnpm 11 和已经安装的工作区依赖；
- 运行时只使用当前 Codex Desktop 随附的 Node 与 Codex。

Tailscale、NPS 和 IIS 都不是本地运行的必需依赖。它们只是不同的远程入口方案。

## V2 进程与端口

V2 的唯一受支持控制目录是 `scripts/windows-v2`；本仓库不再包含旧版控制目录。

| 组件       | 默认监听                             | 暴露范围   |
| ---------- | ------------------------------------ | ---------- |
| Sidecar    | `0.0.0.0:28790` 或 `127.0.0.1:28790` | LAN 或本机 |
| Broker     | `127.0.0.1:28791`                    | 仅本机     |
| app-server | `127.0.0.1:28792`                    | 仅本机     |

浏览器只连接 Sidecar。不得把 Broker、app-server、能力路径或原始 WebSocket
端口转发到局域网或公网。

## 安装和启动

在仓库根目录以管理员身份运行：

```cmd
Start-CodexLocalRemoteV2-OneClick.cmd
```

菜单选项 4 只构建、封存并登记不可变运行代，不改变活动 Desktop。选项 1/2
执行一次明确的冷启动交接：先启动单一 app-server 和 Broker，再让 Desktop 与
Sidecar 接入同一 Broker。V2 不尝试热接管原生 Desktop 的私有 stdio app-server。

计划任务名称为 `Codex Local Remote V2`，必须满足：

- `Interactive`、`Highest`，以当前 Desktop 用户运行；
- 没有登录或定时触发器；
- `StartWhenAvailable=false`；
- `RestartCount=0`；
- 只允许按需启动一个实例。

普通 Desktop 启动、Codex 更新、Windows 登录、重启和睡眠恢复保持原生。

## 监听和安全模式

`lan` 默认绑定 `0.0.0.0:28790`；`localhost` 只绑定回环地址。切换监听模式需要
重启 Sidecar，不要求更换 Broker 或 app-server。

- `insecure-http`：允许 HTTP 会话 Cookie，仅用于本机和受信任局域网诊断；
  密码、同源、CSRF、限速和幂等校验仍然启用。
- `https`：应用按 HTTPS 入口签发安全 Cookie。Sidecar 本身仍然提供 HTTP，TLS
  必须由反向代理终止。

`https` 模式下，反向代理必须从受信任的回环连接提供正确的
`X-Forwarded-Proto` 和 `X-Forwarded-Host`。如果 NPC 与 Remote 在同一台电脑，
NPS 目标应使用 `127.0.0.1:28790`。

## IIS + NPS/NPC

推荐拓扑：

```text
公网浏览器
  -> https://remote.example.com:28790/codex-remote/
  -> 云服务器 IIS HTTPS 28790
  -> http://127.0.0.1:5900/codex-remote/
  -> 云服务器 NPS TCP 5900
  -> 已连接的本地 NPC
  -> 本地 127.0.0.1:28790
```

IIS 与 NPS 位于同一服务器时不能监听同一 IP/TCP 端口。NPS 的 `5900` 只作为
IIS 后端入口；应通过服务器防火墙禁止公网直连，公网只开放 IIS HTTPS 端口。

### NPS

如果 NPC 与 Remote 在同一台电脑：

```text
模式：TCP
服务端端口：5900
目标地址：127.0.0.1:28790
```

如果 NPC 位于同一局域网的另一台电脑，目标才使用 Remote 的局域网地址。

在云服务器上先验证隧道：

```powershell
Test-NetConnection 127.0.0.1 -Port 5900
Invoke-WebRequest -Uri 'http://127.0.0.1:5900/codex-remote/' `
  -UseBasicParsing -TimeoutSec 15
```

必须先看到 Remote 页面，再配置 IIS。TCP 成功但 HTTP 失败，只证明 NPS 监听
存在，不证明 NPC 到 Remote 的整条链路可用。

### IIS

安装并启用 IIS URL Rewrite 2、Application Request Routing 的 `Enable Proxy`、
WebSocket Protocol 和 `Preserve host header`。HTTPS 网站绑定域名、外部端口、
SNI 和对应证书。

网站物理目录中的 `web.config`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <clear />
        <rule name="Codex Local Remote V2" stopProcessing="true">
          <match url="(.*)" />
          <serverVariables>
            <set name="HTTP_X_FORWARDED_PROTO" value="https" />
            <set name="HTTP_X_FORWARDED_HOST" value="{HTTP_HOST}" />
          </serverVariables>
          <action type="Rewrite"
                  url="http://127.0.0.1:5900/{R:1}"
                  appendQueryString="true"
                  logRewrittenUrl="true" />
        </rule>
      </rules>
    </rewrite>
    <security>
      <requestFiltering>
        <requestLimits maxAllowedContentLength="1073741824" />
      </requestFiltering>
    </security>
  </system.webServer>
</configuration>
```

在 URL Rewrite 的“查看服务器变量”中允许：

```text
HTTP_X_FORWARDED_PROTO
HTTP_X_FORWARDED_HOST
```

外部访问 IIS HTTPS 端口，不要访问 NPS 内部端口。使用标准 `443` 时可省略 URL
中的端口号。配置完成后确保 `remote-settings.json` 的 `SecurityMode` 为
`https`，再使用启动菜单选项 1。菜单选项 2 是临时 `insecure-http` 诊断模式，
不适用于这个 HTTPS 入口。

## Tailscale Funnel（可选）

Tailscale Funnel 可以替代 IIS/NPS 提供 HTTPS 入口。它不是本地功能、局域网
功能或 PWA 的构建依赖。不要同时把 Funnel、IIS/NPS 和路由器转发都公开；保留
一个经过验证的 HTTPS 入口即可。

## 状态、更新与验收

固定 dispatcher：

```powershell
$data = Join-Path $env:LOCALAPPDATA 'CodexLocalRemoteV2'
$dispatcher = Join-Path $data 'control\CodexLocalRemoteV2.Dispatcher.ps1'
& (Get-Command pwsh.exe).Source -NoLogo -NoProfile -NonInteractive `
  -File $dispatcher -Operation Status -DataDir $data
```

`Status` 只读。不要持久化 `CODEX_APP_SERVER_WS_URL`，不要手工启动第二个
app-server。Web/Sidecar 更新使用菜单选项 3；Broker、控制脚本或 Desktop 适配
变化使用菜单选项 1/2。

健康结果至少包括：

- `Phase=ready`、`DesktopConnected=True`、`SidecarConnected=True`；
- `28791` 与 `28792` 只监听回环地址；
- Desktop 和 Web 显示相同 thread/turn；
- Desktop 缺失时远程执行失败关闭，而不是启动第二个 app-server。

公网还必须验证 TLS 证书、登录 Cookie、CSRF、实时事件、PWA manifest 和
Service Worker。HTTP 页面能打开不等于 HTTPS 公网部署已经完成。
