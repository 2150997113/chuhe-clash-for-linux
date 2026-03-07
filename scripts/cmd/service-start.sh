#!/usr/bin/env bash
# =========================
# Clash for Linux - 服务启动脚本
# =========================
set -eo pipefail

# DEBUG: 打印失败的行号和命令
trap 'rc=$?; echo "[ERR] rc=$rc line=$LINENO cmd=$BASH_COMMAND" >&2' ERR

# 加载系统函数库 (RHEL Linux)
[ -f /etc/init.d/functions ] && source /etc/init.d/functions

# =========================
# 初始化
# =========================
export SERVER_DIR
SERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# 加载 .env
if [ -f "$SERVER_DIR/.env" ]; then
  set +u
  source "$SERVER_DIR/.env" || echo "[WARN] failed to source .env" >&2
  set -u
fi

SYSTEMD_MODE="${SYSTEMD_MODE:-false}"

# root 权限检查
if [ "$(id -u)" -ne 0 ]; then
  echo "[ERR] root-only mode: please run as root" >&2
  exit 2
fi

# =========================
# 加载公共库
# =========================
# shellcheck disable=SC1090
source "$SERVER_DIR/scripts/lib/output.sh"
output_init

# shellcheck disable=SC1090
source "$SERVER_DIR/scripts/lib/config-check.sh"

# shellcheck disable=SC1090
source "$SERVER_DIR/scripts/lib/cpu-arch.sh"

# shellcheck disable=SC1090
source "$SERVER_DIR/scripts/lib/clash-resolve.sh"

# shellcheck disable=SC1090
source "$SERVER_DIR/scripts/lib/port-check.sh"

# =========================
# 变量设置
# =========================
CONF_DIR="$SERVER_DIR/conf"
TEMP_DIR="$SERVER_DIR/temp"
LOG_DIR="$SERVER_DIR/logs"

mkdir -p "$CONF_DIR" "$TEMP_DIR" "$LOG_DIR" || {
  err "cannot create dirs"
  exit 2
}

PID_FILE="${CLASH_PID_FILE:-$TEMP_DIR/clash.pid}"

# =========================
# 函数定义
# =========================

is_running() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null && return 0
  fi
  return 1
}

ensure_fallback_config() {
  if [ ! -s "$CONF_DIR/config.yaml" ]; then
    if [ -s "$SERVER_DIR/conf/fallback_config.yaml" ]; then
      cp -f "$SERVER_DIR/conf/fallback_config.yaml" "$CONF_DIR/config.yaml"
      warn "已复制 fallback_config.yaml -> conf/config.yaml（兜底）"
    else
      err "未找到可用的 conf/fallback_config.yaml，无法兜底启动"
      [ "${SYSTEMD_MODE:-false}" = "true" ] && return 1 || exit 1
    fi
  fi
  force_write_secret "$CONF_DIR/config.yaml" || {
    err "写入 secret 失败：$CONF_DIR/config.yaml"
    [ "${SYSTEMD_MODE:-false}" = "true" ] && return 1 || exit 1
  }
  return 0
}

ensure_subconverter() {
  local bin="${SERVER_DIR}/libs/subconverter/subconverter"
  local port="25500"

  [ ! -x "$bin" ] && { export SUBCONVERTER_READY="false"; return 0; }

  # 已在监听
  if ss -lntp 2>/dev/null | grep -qE ":${port}[[:space:]]"; then
    export SUBCONVERTER_URL="${SUBCONVERTER_URL:-http://127.0.0.1:${port}}"
    export SUBCONVERTER_READY="true"
    return 0
  fi

  # 启动
  info "starting subconverter..."
  (cd "${SERVER_DIR}/libs/subconverter" && nohup "./subconverter" >/dev/null 2>&1 &)

  for _ in 1 2 3 4 5; do
    sleep 1
    if ss -lntp 2>/dev/null | grep -qE ":${port}[[:space:]]"; then
      export SUBCONVERTER_URL="${SUBCONVERTER_URL:-http://127.0.0.1:${port}}"
      export SUBCONVERTER_READY="true"
      ok "subconverter ready at ${SUBCONVERTER_URL}"
      return 0
    fi
  done

  warn "subconverter start failed"
  export SUBCONVERTER_READY="false"
}

download_subscription() {
  local url="$1" output="$2"
  local rc=0

  # curl
  local curl_cmd=(curl -fL -S --retry 2 --connect-timeout 10 -m 30 -o "$output")
  [ "${ALLOW_INSECURE_TLS:-false}" = "true" ] && curl_cmd+=(-k)
  [ -n "${CLASH_HEADERS:-}" ] && curl_cmd+=(-H "$CLASH_HEADERS")
  curl_cmd+=("$url")

  set +e
  "${curl_cmd[@]}" 2>/dev/null
  rc=$?
  set -e

  # wget fallback
  if [ $rc -ne 0 ]; then
    local wget_cmd=(wget -q -O "$output")
    [ "${ALLOW_INSECURE_TLS:-false}" = "true" ] && wget_cmd+=(--no-check-certificate)
    [ -n "${CLASH_HEADERS:-}" ] && wget_cmd+=(--header="$CLASH_HEADERS")
    wget_cmd+=("$url")

    for _ in {1..3}; do
      set +e
      "${wget_cmd[@]}" 2>/dev/null && rc=0 && break
      set -e
    done
  fi

  return $rc
}

# =========================
# 权限检查
# =========================
chmod +x "$SERVER_DIR/libs/clash/"* 2>/dev/null || true
chmod +x "$SERVER_DIR/scripts/cmd/"* 2>/dev/null || true
chmod +x "$SERVER_DIR/scripts/lib/"* 2>/dev/null || true
[ -f "$SERVER_DIR/libs/subconverter/subconverter" ] && chmod +x "$SERVER_DIR/libs/subconverter/subconverter" 2>/dev/null || true

# 检查是否已在运行
if is_running; then
  ok "Clash 已在运行 (pid=$(cat "$PID_FILE"))，跳过重复启动"
  exit 0
fi

# =========================
# 变量处理
# =========================
URL="${CLASH_URL:-}"
URL="$(printf '%s' "$URL" | tr -d '\r' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
export CLASH_URL="$URL"

# URL 校验
if [ -z "$URL" ] && [ "${SYSTEMD_MODE:-false}" != "true" ]; then
  err "CLASH_URL 为空（未配置订阅地址）"
  exit 2
fi
[ -n "$URL" ] && ! printf '%s' "$URL" | grep -Eq '^https?://' && {
  err "CLASH_URL 格式无效：必须以 http:// 或 https:// 开头"
  exit 2
}

# SECRET 处理
SECRET="${CLASH_SECRET:-}"
[ -z "$SECRET" ] && [ -f "$CONF_DIR/config.yaml" ] && \
  SECRET="$(awk -F': *' '/^[[:space:]]*secret[[:space:]]*:/{print $2; exit}' "$CONF_DIR/config.yaml" 2>/dev/null | tr -d '"' || true)"
[[ "$SECRET" =~ ^\$\{.*\}$ ]] && SECRET=""
if [ -z "$SECRET" ]; then
  SECRET="$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
fi
export SECRET

# 端口默认值
CLASH_HTTP_PORT="${CLASH_HTTP_PORT:-7890}"
CLASH_SOCKS_PORT="${CLASH_SOCKS_PORT:-7891}"
CLASH_REDIR_PORT="${CLASH_REDIR_PORT:-7892}"
CLASH_LISTEN_IP="${CLASH_LISTEN_IP:-127.0.0.1}"
EXTERNAL_CONTROLLER="${EXTERNAL_CONTROLLER:-127.0.0.1:9090}"
ALLOW_INSECURE_TLS="${ALLOW_INSECURE_TLS:-false}"

# 端口解析
CLASH_HTTP_PORT="$(resolve_port_value "HTTP" "$CLASH_HTTP_PORT")"
CLASH_SOCKS_PORT="$(resolve_port_value "SOCKS" "$CLASH_SOCKS_PORT")"
CLASH_REDIR_PORT="$(resolve_port_value "REDIR" "$CLASH_REDIR_PORT")"
EXTERNAL_CONTROLLER="$(resolve_host_port "External Controller" "$EXTERNAL_CONTROLLER" "127.0.0.1")"

# CPU 架构
[ -z "${CPU_ARCH:-}" ] && get_cpu_arch
[ -z "${CPU_ARCH:-}" ] && { err "无法识别 CPU 架构"; exit 2; }

# 临时取消代理
unset http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY || true

# =========================
# systemd 兜底
# =========================
SKIP_CONFIG_REBUILD=false

if [ "${SYSTEMD_MODE}" = "true" ] && [ -z "${URL:-}" ]; then
  warn "SYSTEMD_MODE=true 且 CLASH_URL 为空，跳过订阅更新"
  ensure_fallback_config || true
  SKIP_CONFIG_REBUILD=true
fi

# =========================
# 订阅检测与下载
# =========================
if [ "$SKIP_CONFIG_REBUILD" != "true" ]; then
  info "检测订阅地址..."

  # 检测订阅可访问性
  local check_cmd=(curl -o /dev/null -L -sS --retry 3 -m 10 -w "%{http_code}")
  [ "${ALLOW_INSECURE_TLS}" = "true" ] && check_cmd+=(-k)
  [ -n "${CLASH_HEADERS:-}" ] && check_cmd+=(-H "$CLASH_HEADERS")
  check_cmd+=("$URL")

  set +e
  status_code="$("${check_cmd[@]}" 2>/dev/null)"
  local check_rc=$?
  set -e

  if [ $check_rc -ne 0 ] || ! echo "$status_code" | grep -qE '^[23][0-9]{2}$'; then
    if [ "$SYSTEMD_MODE" = "true" ]; then
      warn "订阅不可访问 (http_code=${status_code:-unknown})，使用兜底配置"
      ensure_fallback_config || true
      SKIP_CONFIG_REBUILD=true
    else
      err "Clash订阅地址不可访问！"
      exit 1
    fi
  fi
fi

# =========================
# 下载配置
# =========================
if [ "$SKIP_CONFIG_REBUILD" != "true" ]; then
  ensure_subconverter || true
  info "下载配置文件..."

  if download_subscription "$URL" "$TEMP_DIR/clash.yaml"; then
    ok "配置文件下载成功"

    # 检查是否是完整 Clash 配置
    if is_full_clash_config "$TEMP_DIR/clash.yaml"; then
      info "订阅已是完整 Clash 配置"
      cp -f "$TEMP_DIR/clash.yaml" "$CONF_DIR/config.yaml"

      # 写入 controller/ui/secret
      force_write_controller_and_ui "$CONF_DIR/config.yaml" || true
      force_write_secret "$CONF_DIR/config.yaml" || true

      # 创建 UI 软链
      [ -d "$SERVER_DIR/dashboard/public" ] && ln -sfn "$SERVER_DIR/dashboard/public" "$CONF_DIR/ui" 2>/dev/null || true

      SKIP_CONFIG_REBUILD=true
    else
      # 需要转换
      info "非完整配置，尝试转换..."
      export IN_FILE="$TEMP_DIR/clash.yaml"
      export OUT_FILE="$TEMP_DIR/clash_converted.yaml"

      set +e
      bash "$SERVER_DIR/scripts/lib/profile-convert.sh"
      local conv_rc=$?
      set -e

      if [ $conv_rc -eq 0 ] && [ -s "$OUT_FILE" ]; then
        cp -f "$OUT_FILE" "$CONF_DIR/config.yaml"
        ok "配置转换成功"
      else
        warn "配置转换失败，使用原始内容"
        cp -f "$TEMP_DIR/clash.yaml" "$CONF_DIR/config.yaml"
      fi

      force_write_controller_and_ui "$CONF_DIR/config.yaml" || true
      force_write_secret "$CONF_DIR/config.yaml" || true
    fi
  else
    if [ "$SYSTEMD_MODE" = "true" ]; then
      warn "配置下载失败，使用兜底配置"
      ensure_fallback_config || true
      SKIP_CONFIG_REBUILD=true
    else
      err "配置文件下载失败！"
      exit 1
    fi
  fi
fi

# =========================
# 启动 Clash
# =========================
CONFIG_FILE="${CONFIG_FILE:-$CONF_DIR/config.yaml}"

[ ! -s "$CONFIG_FILE" ] && { err "config 不存在或为空：$CONFIG_FILE"; exit 2; }
grep -q '\${' "$CONFIG_FILE" && { err "config 包含未解析的占位符"; exit 2; }

info "启动 Clash 服务..."

Clash_Bin="$(resolve_clash_bin "$SERVER_DIR" "$CPU_ARCH")"
[ $? -ne 0 ] && { err "无法解析 Clash 二进制"; exit 2; }

if [ "${SYSTEMD_MODE:-false}" = "true" ]; then
  info "SYSTEMD_MODE=true，前台启动"
  info "config: $CONFIG_FILE"
  exec "$Clash_Bin" -f "$CONFIG_FILE" -d "$CONF_DIR"
else
  info "后台启动 (nohup)"
  nohup "$Clash_Bin" -f "$CONFIG_FILE" -d "$CONF_DIR" >>"$LOG_DIR/clash.log" 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_FILE"
  ok "服务启动成功 (PID: $pid)"
fi

# =========================
# 输出信息
# =========================
echo ""
if [ "${EXTERNAL_CONTROLLER_ENABLED:-true}" = "true" ]; then
  echo "Clash Dashboard: http://${EXTERNAL_CONTROLLER}/ui"
  local masked="${SECRET:0:4}****${SECRET: -4}"
  echo "SECRET: ${masked}"
else
  echo "External Controller 已禁用"
fi
echo ""
