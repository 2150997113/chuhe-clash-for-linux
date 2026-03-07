#!/usr/bin/env bash
# =========================
# Clash for Linux - 服务重启脚本
# =========================
set -euo pipefail

# 获取项目根目录
SERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# =========================
# 加载公共库
# =========================
# shellcheck disable=SC1090
source "$SERVER_DIR/scripts/lib/output.sh"
output_init

# =========================
# 检查参数
# =========================
if [ "${1:-}" = "--update" ]; then
  info "更新订阅..."
  bash "$SERVER_DIR/scripts/cmd/subscription-update.sh" || exit 1
fi

# =========================
# 停止服务
# =========================
info "停止服务..."

if [ -f "$SERVER_DIR/scripts/cmd/service-stop.sh" ]; then
  bash "$SERVER_DIR/scripts/cmd/service-stop.sh" || true
else
  # 兜底：直接杀进程
  PID_FILE="$SERVER_DIR/temp/clash.pid"
  if [ -f "$PID_FILE" ]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      for _ in {1..5}; do
        sleep 1
        kill -0 "$pid" 2>/dev/null || break
      done
      kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
  fi
fi

sleep 2

# =========================
# 启动服务
# =========================
info "启动服务..."

if [ -f "$SERVER_DIR/scripts/cmd/service-start.sh" ]; then
  bash "$SERVER_DIR/scripts/cmd/service-start.sh"
else
  # 兜底：直接启动
  CONF_DIR="$SERVER_DIR/conf"
  LOG_DIR="$SERVER_DIR/logs"
  TEMP_DIR="$SERVER_DIR/temp"
  PID_FILE="$TEMP_DIR/clash.pid"

  # shellcheck disable=SC1090
  source "$SERVER_DIR/scripts/lib/cpu-arch.sh"
  # shellcheck disable=SC1090
  source "$SERVER_DIR/scripts/lib/clash-resolve.sh"

  [ -z "${CPU_ARCH:-}" ] && get_cpu_arch
  Clash_Bin="$(resolve_clash_bin "$SERVER_DIR" "$CPU_ARCH")"

  nohup "$Clash_Bin" -d "$CONF_DIR" >>"$LOG_DIR/clash.log" 2>&1 &
  echo $! > "$PID_FILE"
fi

ok "服务重启完成"
