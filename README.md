# dsh-mac-access

Windows 访问 Mac DSH 的跨机链路管理插件：注册一个 `mac-access` skill，指导 agent 调用随包脚本完成体检、推送登录 URL、部署 Windows 一键脚本。

链路是通用的（不是某台机器的专配）：Mac 上 DSH GUI 绑一个局域网地址 → 一个周期任务把最新的带 token 登录 URL 推给 Windows → Windows 桌面快捷方式读该文件打开浏览器。所有机器相关值都在 `tools/config.local.env` 里填。

## 链路背景

- Mac DSH GUI 绑**具体局域网 IP**（DSH 拒绝 `0.0.0.0` 通配符，只能绑具体接口；Mac IP 变化会导致服务起不来）
- Mac LaunchAgent（默认 label `com.user.dsh-url-push`）每 60s 把最新登录 URL 推到 Windows 侧的一个文件
- Windows 双击桌面快捷方式「Mac DSH」→ `open-mac-dsh.ps1` 读该文件开浏览器（DSH 每次重启都换 token，所以永远用脚本开，不要手输旧地址）

## 插件内容

- `index.js`：cordis 插件，`ctx.skills.register` 注册 `mac-access` skill
- `skill.md`：skill 指令正文（子命令用法、完成标准、红线）
- `tools/mac-access.sh`：`check` / `push` / `win-setup` 三个子命令
- `tools/config.example.env`：链路配置模板
- `templates/`：Windows 侧文件模板（ps1 / cmd / 桌面快捷方式生成）

## 安装

1. `cordis.patch.yml` 里已有挂载条目（insert `dsh-mac-access`），`toolsPath` 默认取随包路径
2. 把本包加进 web profile 依赖（本地仓 link 或 `file:`），重启 GUI 生效
3. 复制 `tools/config.example.env` → `tools/config.local.env`，按你的链路填 5 个必填项

## 使用

会话里说「检查 Windows 访问 Mac DSH 的链路」或「把最新地址推给 Windows」，agent 会加载 skill 并执行对应子命令；也可以手动：

```bash
bash tools/mac-access.sh check      # 五项体检，只读
bash tools/mac-access.sh push       # 立即推送最新登录 URL
bash tools/mac-access.sh win-setup  # 部署/修复 Windows 侧 ps1+cmd+桌面快捷方式
```

## 红线

- token 是登录凭证，输出一律脱敏（尾 4 位）
- 跨机只用 Mac→Windows 方向（Windows→Mac 的 sshd 若有已知故障，不要依赖它）
- 不擅自改 DSH 配置 / 重启 GUI / 删用户文件
