#!/bin/bash
# mac-access.sh — Windows 访问 Mac DSH 链路运维（随包脚本，由 mac-access skill 指导 agent 调用）
# 子命令：check（五项体检）/ push（立即推送最新登录 URL）/ win-setup（部署修复 Windows 侧文件）
# 无任何密钥；token 只做比对、不落盘、不打印。
#
# 配置：复制 tools/config.example.env 为 tools/config.local.env（已在 .gitignore），
# 或用环境变量传入；也可用 MAC_ACCESS_CONF 指向别的配置文件。
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
CONF="${MAC_ACCESS_CONF:-$HERE/config.local.env}"
# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

: "${MAC_DSH_WIN_HOST:=}"
: "${MAC_DSH_WIN_TOOLS_DIR:=}"
: "${MAC_DSH_WIN_URL_FILE:=}"
: "${MAC_DSH_LOG:=$HOME/Library/Logs/dsh-web.out.log}"
: "${MAC_DSH_LAN_BASE:=}"
: "${MAC_DSH_LAUNCHD_LABEL:=com.user.dsh-url-push}"
: "${MAC_DSH_PUSH_LOG:=/tmp/dsh-url-push.log}"
: "${MAC_DSH_LNK_NAME:=Mac DSH.lnk}"

TPL_DIR="$(cd "$HERE/../templates" 2>/dev/null && pwd)"
TMP_URL="$(mktemp -t mac-access-url)"
SSH=(/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=8)
SCP=(/usr/bin/scp -O -o BatchMode=yes -o ConnectTimeout=8)

say()  { printf '%s\n' "$*"; }
ok()   { say "OK   $*"; }
bad()  { say "BAD  $*"; }

need() {
  local miss=0 v val
  for v in "$@"; do
    eval "val=\${$v-}"
    if [ -z "$val" ]; then
      bad "未配置 ${v}（写进 $HERE/config.local.env，参考 config.example.env）"
      miss=1
    fi
  done
  [ "$miss" -eq 0 ]
}

url_hostport() { printf '%s' "${MAC_DSH_LAN_BASE#http://}" | /usr/bin/sed 's:/.*$::'; }
land_port()    { url_hostport | /usr/bin/sed 's/.*://'; }

current_url() {
  /usr/bin/tail -200 "$MAC_DSH_LOG" 2>/dev/null | /usr/bin/grep -oE 'http://[^ ]+\?token=[^ ]*' | /usr/bin/tail -1
}
current_token() { current_url | /usr/bin/grep -oE 'token=[A-Za-z0-9._-]+' | /usr/bin/cut -d= -f2; }
mask() { printf '%s' "${1: -4}"; }

# ---- check：五项体检，只读 ----
check() {
  need MAC_DSH_LAN_BASE MAC_DSH_LOG MAC_DSH_WIN_HOST MAC_DSH_WIN_URL_FILE MAC_DSH_WIN_TOOLS_DIR || return 2
  local fails=0

  # 1) GUI 绑局域网 IP
  if /usr/sbin/lsof -nP -iTCP:"$(land_port)" -sTCP:LISTEN 2>/dev/null | /usr/bin/grep -qF "$(url_hostport)"; then
    ok "GUI 绑定 $MAC_DSH_LAN_BASE"
  else
    bad "GUI 未绑定 ${MAC_DSH_LAN_BASE}（当前监听：$(/usr/sbin/lsof -nP -iTCP:"$(land_port)" -sTCP:LISTEN 2>/dev/null | /usr/bin/tail -1)）"; fails=$((fails+1))
  fi

  # 2) 当前 token 有效（/connect 302）
  local tok; tok=$(current_token)
  if [ -z "$tok" ]; then bad "日志里没有带 token 的登录 URL（${MAC_DSH_LOG}）"; fails=$((fails+1)); else
    local code; code=$(/usr/bin/curl -s -m 8 -o /dev/null -w '%{http_code}' "$MAC_DSH_LAN_BASE/connect?token=${tok}&interactions=answer" 2>/dev/null)
    if [ "$code" = "302" ]; then ok "当前 token 有效（尾 4 位 $(mask "$tok")，/connect 302）"; else bad "当前 token /connect 返回 ${code}（预期 302）"; fails=$((fails+1)); fi
  fi

  # 3) push LaunchAgent（StartInterval 周期任务，平时 not running 属正常；已加载即可）
  if /bin/launchctl print "gui/$(id -u)/$MAC_DSH_LAUNCHD_LABEL" >/dev/null 2>&1; then
    ok "url-push LaunchAgent 已加载（最后推送：$(/usr/bin/tail -1 "$MAC_DSH_PUSH_LOG" 2>/dev/null)）"
  else
    bad "url-push LaunchAgent 未加载（${MAC_DSH_LAUNCHD_LABEL}）"; fails=$((fails+1))
  fi

  # 4) Windows 侧 URL 文件 token 与当前一致
  local winurl; winurl=$("${SSH[@]}" "$MAC_DSH_WIN_HOST" "cmd /c type \"$MAC_DSH_WIN_URL_FILE\"" 2>/dev/null | /usr/bin/head -1)
  local wintok; wintok=$(printf '%s' "$winurl" | /usr/bin/grep -oE 'token=[A-Za-z0-9._-]+' | /usr/bin/cut -d= -f2)
  if [ -n "$wintok" ] && [ -n "$tok" ] && [ "$wintok" = "$tok" ]; then
    ok "Windows URL 文件 token 一致（尾 4 位 $(mask "$wintok")）"
  else
    bad "Windows URL 文件 token 不一致或缺失（win 尾 4 位 $(mask "$wintok") / mac 尾 4 位 $(mask "$tok")）"; fails=$((fails+1))
  fi

  # 5) Windows 脚本与桌面快捷方式
  local ps r
  ps="Write-Output ((Test-Path '${MAC_DSH_WIN_TOOLS_DIR}\\open-mac-dsh.ps1') -and (Test-Path '${MAC_DSH_WIN_TOOLS_DIR}\\open-mac-dsh.cmd') -and (Test-Path (Join-Path ([Environment]::GetFolderPath('Desktop')) '${MAC_DSH_LNK_NAME}')))"
  r=$("${SSH[@]}" "$MAC_DSH_WIN_HOST" "powershell -NoProfile -Command \"$ps\"" 2>/dev/null | /usr/bin/tr -d '\r')
  if [ "$r" = "True" ]; then ok "Windows 脚本与桌面快捷方式齐全"; else bad "Windows 侧文件缺失（ps1+cmd+桌面快捷方式 结果=${r}）"; fails=$((fails+1)); fi

  say "----"
  if [ "$fails" -eq 0 ]; then say "check 全绿"; else say "check 有 $fails 项 BAD"; fi
  return "$fails"
}

# ---- push：立即推送最新登录 URL ----
push() {
  need MAC_DSH_LOG MAC_DSH_WIN_HOST MAC_DSH_WIN_URL_FILE || return 2
  local url; url=$(current_url)
  if [ -z "$url" ]; then bad "日志里没有带 token 的登录 URL（${MAC_DSH_LOG}）"; return 1; fi
  printf '%s\n' "$url" > "$TMP_URL"
  if "${SCP[@]}" "$TMP_URL" "${MAC_DSH_WIN_HOST}:${MAC_DSH_WIN_URL_FILE}" 2>/dev/null; then
    printf '%s\n' "$url" > "$MAC_DSH_PUSH_LOG"
    say "已推送最新 URL 到 ${MAC_DSH_WIN_HOST}:${MAC_DSH_WIN_URL_FILE}（token 尾 4 位 $(mask "$(printf '%s' "$url" | /usr/bin/grep -oE 'token=[A-Za-z0-9._-]+' | /usr/bin/cut -d= -f2)")）"
  else
    bad "scp 推送失败（检查 Mac→Windows 免密 SSH）"; return 1
  fi
}

# ---- win-setup：部署/修复 Windows 侧三个文件 ----
win_setup() {
  need MAC_DSH_WIN_HOST MAC_DSH_WIN_TOOLS_DIR || return 2
  local fails=0
  # 1) ps1 与 cmd（cmd 需 CRLF，模板为 LF，就地转换）
  "${SCP[@]}" "$TPL_DIR/open-mac-dsh.ps1" "${MAC_DSH_WIN_HOST}:${MAC_DSH_WIN_TOOLS_DIR}\\open-mac-dsh.ps1" 2>/dev/null || { bad "推送 open-mac-dsh.ps1 失败"; fails=$((fails+1)); }
  /usr/bin/sed 's/$/\r/' "$TPL_DIR/open-mac-dsh.cmd" > "$TMP_URL.cmd"
  "${SCP[@]}" "$TMP_URL.cmd" "${MAC_DSH_WIN_HOST}:${MAC_DSH_WIN_TOOLS_DIR}\\open-mac-dsh.cmd" 2>/dev/null || { bad "推送 open-mac-dsh.cmd 失败"; fails=$((fails+1)); }
  # 2) 桌面快捷方式（make-lnk.ps1 用 -ToolsDir 参数，不依赖固定盘符）
  "${SCP[@]}" "$TPL_DIR/make-lnk.ps1" "${MAC_DSH_WIN_HOST}:${MAC_DSH_WIN_TOOLS_DIR}\\make-lnk.ps1" 2>/dev/null && \
  "${SSH[@]}" "$MAC_DSH_WIN_HOST" "powershell -NoProfile -ExecutionPolicy Bypass -File \"${MAC_DSH_WIN_TOOLS_DIR}\\make-lnk.ps1\" -ToolsDir \"${MAC_DSH_WIN_TOOLS_DIR}\" -LnkName \"${MAC_DSH_LNK_NAME}\"" >/dev/null 2>&1 && \
  "${SSH[@]}" "$MAC_DSH_WIN_HOST" "powershell -NoProfile -Command \"Remove-Item '${MAC_DSH_WIN_TOOLS_DIR}\\make-lnk.ps1' -Force\"" >/dev/null 2>&1 || { bad "重建桌面快捷方式失败"; fails=$((fails+1)); }
  if [ "$fails" -eq 0 ]; then ok "win-setup 完成（ps1+cmd+桌面快捷方式）"; else bad "win-setup 有 $fails 项失败"; fi
  return "$fails"
}

case "${1:-}" in
  check)     check;;
  push)      push;;
  win-setup) win_setup;;
  *) say "用法: mac-access.sh <check|push|win-setup>"; exit 2;;
esac
