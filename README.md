# 抖音聊天多开管理器 / Douyin Chat Multi-Instance Manager

> 一台 Windows 电脑同时运行多个抖音聊天实例，每个实例独立登录不同账号。
>
> Run multiple Douyin Chat (Electron) instances on one Windows PC, each with its own login session.

---

## 功能 / Features

### 中文

- **多实例管理**: 一键启动/停止/新建/删除实例
- **三指标仪表盘**: 进程状态、客户端状态、凭据有效性独立显示
- **凭据检测**: 未运行实例读取 Cookie 数据库检测 sessionid 有效期；运行中实例通过 Cookie 文件刷新时间判断
- **系统监控**: CPU/内存/温度/频率/出口IP
- **安全退出**: 不强杀进程，避免账号掉线
- **开机自启**: Windows 计划任务自动启动所有实例

### English

- **Multi-instance management**: Start/stop/create/delete instances with one click
- **3-indicator dashboard**: Process status, client status, and credential validity shown independently
- **Credential detection**: Reads Cookie DB for stopped instances; checks Cookie file refresh time for running ones
- **System monitoring**: CPU, memory, temperature, frequency, public IP
- **Safe exit**: Graceful shutdown only — never force-kills processes
- **Auto-start**: Windows scheduled task launches all instances on login

---

## 原理 / How It Works

抖音聊天是 Electron 应用 (v1.1.33)。通过修改 `app.asar` 中的 `index.js` 实现多开：

Douyin Chat is an Electron app (v1.1.33). Multi-instance is achieved by patching `app.asar`:

1. **绕过单实例锁 / Bypass single-instance lock**:
   ```
   // Before
   if(!e.app.requestSingleInstanceLock()) return e.app.quit(-1), !0
   // After
   if(!1) return e.app.quit(-1), !0
   ```

2. **独立数据目录 / Isolate data directories**:
   ```
   // Before: setPath("userData", .../抖音聊天")
   // After:  setPath("userData", .../抖音聊天N")  // N = instance ID
   ```

### 不做的事情 / What NOT to do

- ❌ 不改 `package.json` 的 `name` / `productName` — 会触发服务端校验导致登录崩溃
- ❌ 不注入硬件指纹覆盖 — 会触发反篡改检测

---

## 文件说明 / File Structure

| 文件 / File | 用途 / Purpose |
|---|---|
| `manager.ps1` | 管理器主脚本 / Main manager script (dashboard + operations) |
| `instances.json` | 实例配置 / Instance config (id, directory, nickname) |
| `check_credential.js` | 凭据检测脚本 / Credential checker (reads sessionid from Cookie DB) |
| `patch_fingerprint.js` | 补丁脚本 / Patch script (bypass lock + isolate data dir) |
| `read_cookie.js` | Cookie 读取 / Cookie reader |
| `check_login.js` | 登录状态检查 / Login status checker |
| `start_all.ps1` | 开机自启脚本 / Auto-start script |
| `启动小号.bat` | 桌面入口 / Desktop shortcut target |
| `docs/` | 技术文档 / Technical documentation |

---

## 使用方法 / Usage

### 首次安装 / First Setup

1. 安装抖音聊天 PC 版 v1.1.33
2. 安装 Node.js
3. 在项目目录运行 `npm install` 安装依赖
4. 运行 `启动小号.bat` 或 `powershell manager.ps1`

### 日常使用 / Daily Use

```
[M] 主实例    [1-9] 小号      [A] 全部启动
[S] 全部停止  [N] 新建实例    [D] 删除实例
[E] 编辑备注  [R] 刷新        [Q] 退出
```

### 重启前必做 / Before Reboot

**按 `S` 安全关闭所有实例，等待"全部已安全关闭"后再重启。**

**Press `S` to safely close all instances. Wait for "all closed safely" before rebooting.**

直接重启/断电会导致所有账号掉线（IM SDK 未正常释放，服务端强制下线）。

Rebooting without closing causes all accounts to log out (IM SDK not released, server forces disconnect).

---

## 三指标说明 / Dashboard Indicators

| 指标 / Indicator | 含义 / Meaning |
|---|---|
| **进程 / Process** | douyinim.exe 是否在运行 / Whether the process is running |
| **客户端 / Client** | 窗口标题: 在线/需登录 / Window title: online/login required |
| **凭据 / Credential** | sessionid 有效期 / Cookie refresh status |

### 凭据状态 / Credential Status

| 状态 / Status | 含义 / Meaning |
|---|---|
| `有效，剩余X天` | Cookie 有效，X天后过期 / Valid, expires in X days |
| `有效(刷新于X分钟前)` | 运行中，Cookie 刚刷新过 / Running, recently refreshed |
| `可能掉线(无刷新X分钟)` | 运行中但Cookie长时间未刷新 / Running but no refresh for X min |
| `需重新登录` | 窗口显示需登录 / Client shows login required |
| `session已失效` | sessionid 不在Cookie中 / sessionid missing from Cookie DB |
| `已过期` | sessionid 已过期 / sessionid expired |

---

## 掉线风险 / Disconnection Risks

| 场景 / Scenario | 风险 / Risk | 预防 / Prevention |
|---|---|---|
| 重启电脑 / Reboot | ⚠️ 高 | 先按 S 安全关闭 / Press S first |
| 断电 / Power loss | ⚠️ 高 | 使用 UPS / Use UPS |
| 长时间闲置 / Long idle | 🟡 中 | 定期检查 / Check periodically |
| 60天Cookie过期 / 60-day expiry | 🟡 中 | 到期前重新扫码 / Re-scan before expiry |

---

## 技术文档 / Technical Docs

详见 `docs/` 目录：

See `docs/` directory:

- `项目归档-20260831.md` — 项目归档（中文）
- `抖音多开管理器-技术文档.md` — 核心逻辑文档（中文）
- `file_260830_231411_90783.md` — 逆向分析报告（中文）

---

## 环境要求 / Requirements

- Windows 10/11
- Node.js (for credential checker)
- PowerShell 5.1+
- 抖音聊天 PC 版 v1.1.33

---

## 许可 / License

仅供学习交流使用。请遵守抖音用户协议。

For educational and research purposes only. Please comply with Douyin's Terms of Service.

---

*jianhx 2026*
