#!/usr/bin/env bash
# =========================
# Clash for Linux - 卸载脚本
# =========================
set -euo pipefail

# 获取项目根目录
SERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_DIR="$SERVER_DIR"
SERVICE_NAME="clash-for-linux"

# =========================
# 加载公共库
# =========================
# shellcheck disable=SC1090
source "$INSTALL_DIR/scripts/lib/output.sh"
output_init

# =========================
# 权限检查
# =========================
if [ "$(id -u)" -ne 0 ]; then
  err "需要 root 权限执行卸载脚本（请使用 sudo just uninstall）"
  exit 1
fi

info "开始卸载 ${SERVICE_NAME} ..."

# =========================
# 0) 关闭系统代理
# =========================
info "关闭系统代理..."

# 尝试调用已安装的 proxy_down 函数
if [ -f "/etc/profile.d/clash-for-linux.sh" ]; then
  source "/etc/profile.d/clash-for-linux.sh" 2>/dev/null || true
  if type proxy_down >/dev/null 2>&1; then
    proxy_down 2>/dev/null || true
  fi
fi

# 兜底：直接清除代理环境变量
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY no_proxy NO_PROXY 2>/dev/null || true

ok "已关闭系统代理"

# =========================
# 1) 停止服务
# =========================
if [ -f "${INSTALL_DIR}/scripts/cmd/service-stop.sh" ]; then
  info "停止服务..."
  bash "${INSTALL_DIR}/scripts/cmd/service-stop.sh" >/dev/null 2>&1 || true
fi

# systemd 停止
if command -v systemctl >/dev/null 2>&1; then
  info "停止 systemd 服务..."
  systemctl stop "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
  systemctl disable "${SERVICE_NAME}.service" >/dev/null 2>&1 || true
fi

# 兜底：按 PID 文件停止
PID_FILE="${INSTALL_DIR}/temp/clash.pid"
if [ -f "$PID_FILE" ]; then
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
fi

# 兜底：按进程名停止
if pgrep -x clash >/dev/null 2>&1; then
  warn "检测到残留 clash 进程，尝试结束..."
  pkill -x clash 2>/dev/null || true
  sleep 1
  pgrep -x clash >/dev/null 2>&1 && pkill -9 -x clash 2>/dev/null || true
fi

# =========================
# 2) 删除 systemd unit
# =========================
Unit_Path="/etc/systemd/system/${SERVICE_NAME}.service"

if [ -f "$Unit_Path" ]; then
  rm -f "$Unit_Path"
  ok "已移除: ${Unit_Path}"
fi

if [ -d "/etc/systemd/system/${SERVICE_NAME}.service.d" ]; then
  rm -rf "/etc/systemd/system/${SERVICE_NAME}.service.d"
  ok "已移除: /etc/systemd/system/${SERVICE_NAME}.service.d"
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl reset-failed >/dev/null 2>&1 || true
fi

# =========================
# 3) 清理配置文件
# =========================
[ -f "/etc/default/${SERVICE_NAME}" ] && rm -f "/etc/default/${SERVICE_NAME}" && ok "已移除: /etc/default/${SERVICE_NAME}"
[ -f "/etc/profile.d/clash-for-linux.sh" ] && rm -f "/etc/profile.d/clash-for-linux.sh" && ok "已移除: /etc/profile.d/clash-for-linux.sh"
[ -f "${INSTALL_DIR}/temp/clash-for-linux.sh" ] && rm -f "${INSTALL_DIR}/temp/clash-for-linux.sh" && ok "已移除: ${INSTALL_DIR}/temp/clash-for-linux.sh"
[ -f "/usr/local/bin/clashctl" ] && rm -f "/usr/local/bin/clashctl" && ok "已移除: /usr/local/bin/clashctl"
[ -f "/usr/local/bin/m" ] && rm -f "/usr/local/bin/m" && ok "已移除: /usr/local/bin/m"

# =========================
# 4) 完成
# =========================
info "项目目录保留: ${INSTALL_DIR}"
info "如需完全删除，请手动执行: rm -rf ${INSTALL_DIR}"

echo
ok "卸载完成 ✅"
