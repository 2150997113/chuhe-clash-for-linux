#!/usr/bin/env bash
set -euo pipefail

# 作用：
# - 根据 OS/ARCH 选择 libs/subconverter/<platform>/subconverter
# - 生成稳定入口 libs/subconverter/subconverter（软链优先，失败则复制）
# -（可选）以 daemon 模式启动本地 subconverter（HTTP 服务）
# - 导出统一变量给后续脚本使用：
#   SUBCONVERTER_BIN / SUBCONVERTER_READY / SUBCONVERTER_URL
#
# 设计原则：
# - 永不 exit 1（不可用就 Ready=false，主流程继续）
# - 不阻塞 start.sh（快速启动，不等待健康检查）

SERVER_DIR="${SERVER_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TEMP_DIR="${TEMP_DIR:-$SERVER_DIR/temp}"

mkdir -p "$TEMP_DIR"

SC_DIR="$SERVER_DIR/libs/subconverter"
SC_LINK="$SC_DIR/subconverter"   # 稳定入口（最终用于启动/调用）
SUBCONVERTER_BIN="$SC_LINK"
SUBCONVERTER_READY=false

# 配置项（可放 .env）
SUBCONVERTER_MODE="${SUBCONVERTER_MODE:-daemon}"     # daemon | off
SUBCONVERTER_HOST="${SUBCONVERTER_HOST:-127.0.0.1}"
SUBCONVERTER_PORT="${SUBCONVERTER_PORT:-25500}"
SUBCONVERTER_URL="${SUBCONVERTER_URL:-http://${SUBCONVERTER_HOST}:${SUBCONVERTER_PORT}}"

# pref.ini：不存在就从示例生成
SUBCONVERTER_PREF="${SUBCONVERTER_PREF:-$SC_DIR/pref.ini}"
PREF_EXAMPLE_INI="$SC_DIR/pref.example.ini"

PID_FILE="$TEMP_DIR/subconverter.pid"

log()  { echo "[subc] $*"; }
warn() { echo "[subc][WARN] $*" >&2; }

detect_os() {
  local u
  u="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$u" in
    linux*) echo "linux" ;;
    *) echo "unsupported" ;;
  esac
}

detect_arch() {
  local m
  m="$(uname -m | tr '[:upper:]' '[:lower:]')"
  case "$m" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv7) echo "armv7" ;;
    *) echo "unknown" ;;
  esac
}

pick_platform_bin() {
  # 新的仓库结构：libs/subconverter/linux-amd64/subconverter 等
  local os="$1" arch="$2"
  local p="$SC_DIR/${os}-${arch}/subconverter"
  if [ -f "$p" ]; then
    echo "$p"
    return 0
  fi
  echo ""
  return 0
}

make_stable_link_or_copy() {
  local src="$1"

  # 确保可执行
  chmod +x "$src" 2>/dev/null || true

  # 清理旧入口
  rm -f "$SC_LINK" 2>/dev/null || true

  # 软链优先，不支持则复制
  if ln -s "$src" "$SC_LINK" 2>/dev/null; then
    :
  else
    cp -f "$src" "$SC_LINK" 2>/dev/null || return 1
    chmod +x "$SC_LINK" 2>/dev/null || true
  fi
  return 0
}

is_port_listening() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lnt | awk '{print $4}' | grep -q ":${port}\$" && return 0
  fi
  # 兜底：ss 不存在就不判断（返回 false）
  return 1
}

main() {
  # 0) 用户显式关闭
  if [ "$SUBCONVERTER_MODE" = "off" ]; then
    SUBCONVERTER_READY=false
    export SUBCONVERTER_BIN SUBCONVERTER_READY SUBCONVERTER_BIN SUBCONVERTER_READY SUBCONVERTER_URL
    true
    return 0
  fi

  # 1) 选择平台二进制
  local os arch platform_bin
  os="$(detect_os)"
  arch="$(detect_arch)"

  if [ "$os" = "unsupported" ]; then
    warn "Unsupported OS: $(uname -s). Skip subconverter."
    SUBCONVERTER_READY=false
    export SUBCONVERTER_BIN SUBCONVERTER_READY SUBCONVERTER_BIN SUBCONVERTER_READY SUBCONVERTER_URL
    true
    return 0
  fi

  if [ "$arch" = "unknown" ]; then
    warn "Unsupported arch: $(uname -m). Skip subconverter."
    SUBCONVERTER_READY=false
    export SUBCONVERTER_BIN SUBCONVERTER_READY SUBCONVERTER_BIN SUBCONVERTER_READY SUBCONVERTER_URL
    true
    return 0
  fi

  platform_bin="$(pick_platform_bin "$os" "$arch")"
  if [ -z "$platform_bin" ]; then
    warn "No subconverter binary found at: $SC_DIR/${os}-${arch}/subconverter"
    SUBCONVERTER_READY=false
    export SUBCONVERTER_BIN SUBCONVERTER_READY SUBCONVERTER_BIN SUBCONVERTER_READY SUBCONVERTER_URL
    true
    return 0
  fi

  # 2) 生成稳定入口 libs/subconverter/subconverter
  if ! make_stable_link_or_copy "$platform_bin"; then
    warn "Failed to create stable entry: $SC_LINK"
    SUBCONVERTER_READY=false
    export SUBCONVERTER_BIN SUBCONVERTER_READY SUBCONVERTER_BIN SUBCONVERTER_READY SUBCONVERTER_URL
    true
    return 0
  fi

  SUBCONVERTER_BIN="$SC_LINK"
  SUBCONVERTER_READY=true
  log "Resolved platform bin: ${os}-${arch} -> $SUBCONVERTER_BIN"

  # 3) pref.ini 生成（仅当准备启用 daemon）
  if [ "$SUBCONVERTER_READY" = "true" ] && [ "$SUBCONVERTER_MODE" = "daemon" ]; then
    if [ ! -f "$SUBCONVERTER_PREF" ] && [ -f "$PREF_EXAMPLE_INI" ]; then
      cp -f "$PREF_EXAMPLE_INI" "$SUBCONVERTER_PREF"
    fi
  fi

  # 4) daemon 启动（只在需要时）
  if [ "$SUBCONVERTER_READY" = "true" ] && [ "$SUBCONVERTER_MODE" = "daemon" ]; then
    # pid 存活则认为已启动
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
      :
    else
      # 端口已监听则不重复起（可能是之前启动的）
      if is_port_listening "$SUBCONVERTER_PORT"; then
        :
      else
        (
          cd "$SC_DIR"
          # 注意：subconverter 读取 base/rules/snippets 等目录，必须在其目录下启动更稳
          nohup "$SUBCONVERTER_BIN" -f "$SUBCONVERTER_PREF" >/dev/null 2>&1 &
          echo $! > "$PID_FILE"
        )
        # 给一点点启动时间（不要长等，避免阻塞）
        sleep 0.2
      fi
    fi
  fi

  # 5) 统一导出（给后续脚本用）
  export SUBCONVERTER_BIN
  export SUBCONVERTER_READY
  export SUBCONVERTER_BIN="$SUBCONVERTER_BIN"
  export SUBCONVERTER_READY="$SUBCONVERTER_READY"
  export SUBCONVERTER_URL

  # 永不失败
  true
}

main "$@"
