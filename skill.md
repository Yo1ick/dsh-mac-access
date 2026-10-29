# mac-access — Windows 访问 Mac DSH 链路管理

## 用途

把 Mac 端 DSH GUI 暴露给 Windows 使用的跨机链路运维：体检、推送登录 URL、部署 Windows 一键脚本与桌面快捷方式。

链路构成（通用，机器相关值见 `tools/config.local.env`）：
- Mac GUI 绑**具体局域网 IP**（DSH 拒绝 0.0.0.0 通配符，只能绑具体接口 IP；Mac IP 变化会导致服务起不来）
- Mac LaunchAgent（默认 `com.user.dsh-url-push`）每 60s 把最新登录 URL 推到 Windows 侧的一个文件（走 Mac→Windows 免密 SSH）
- Windows 一键脚本 `open-mac-dsh.ps1`（读该文件开浏览器）+ 双击版 `open-mac-dsh.cmd` + 桌面快捷方式「Mac DSH」

## 何时使用

用户提到「Windows 访问 Mac DSH」「token 过期」「打开 Mac DSH 的脚本/快捷方式」「链路不通/体检」时使用本 skill。

## 前置：配置

脚本读 `tools/config.local.env`（同目录，已在 .gitignore）。若不存在，按 `config.example.env` 复制并填：

- `MAC_DSH_WIN_HOST`：Windows SSH 目标（如 `user@host`）
- `MAC_DSH_WIN_TOOLS_DIR`：Windows 侧脚本目录（无反斜杠结尾）
- `MAC_DSH_WIN_URL_FILE`：Windows 侧登录 URL 文件
- `MAC_DSH_LAN_BASE`：Mac GUI 的局域网地址（如 `http://<mac-ip>:3080`）

配置缺失时脚本会打印 `BAD 未配置 …` 并以退出码 2 结束，不要绕过——先把配置补齐。

## 工具

随包脚本：`__TOOLS_PATH__`（三个子命令）

### 1. 体检：`bash __TOOLS_PATH__ check`

只读检查五项：GUI 绑 LAN IP、当前 token 有效（/connect 302）、push LaunchAgent 状态、Windows 侧 URL 文件 token 与当前一致、Windows 脚本与桌面快捷方式存在。退出码 0 = 全绿；非 0 = 有 BAD 项（输出里带 BAD 标记）。

### 2. 立即推送：`bash __TOOLS_PATH__ push`

强制把最新登录 URL 推到 Windows（不等 60s 周期）。GUI 重启后若用户急着在 Windows 打开，先跑这条。

### 3. 部署/修复 Windows 侧：`bash __TOOLS_PATH__ win-setup`

把随包模板的 open-mac-dsh.ps1 / open-mac-dsh.cmd 推到 `MAC_DSH_WIN_TOOLS_DIR`，并重建桌面快捷方式「Mac DSH」（目标桌面目录自动探测，可能是非 C 盘）。Windows 侧文件丢失/损坏时用它修复。

## 完成标准

- check 输出全部 OK、退出码 0
- 按用户要求执行 push 或 win-setup 后复跑 check 确认

## 红线与注意

- **token 是登录凭证**：任何输出都要脱敏（只显示尾 4 位或 <redacted>），不把完整 token 写进回复、文件或记忆
- **跨机操作只走 Mac→Windows 方向**（Windows→Mac 的 sshd 若有已知故障，勿依赖）
- 不擅自改 DSH 配置、不重启 GUI、不删用户文件；win-setup 只覆盖插件自管的三个 Windows 文件
- Mac 本机 IP 变了要先处理绑定问题（check 第 1 项会暴露），不要盲改
