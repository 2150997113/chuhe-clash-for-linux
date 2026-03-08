#!/bin/bash
# =========================
# Clash 配置工具库
# 提供 YAML 配置操作
# =========================

# 清理值的首尾空格
trim_value() {
  local value="$1"
  echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# =========================
# YAML 操作
# =========================

# 写入/更新 YAML 顶级 key
upsert_yaml_kv() {
  local file="$1" key="$2" value="$3"
  [ -n "$file" ] && [ -n "$key" ] || return 1

  [ -f "$file" ] || : >"$file" || return 1

  if grep -qE "^[[:space:]]*${key}:[[:space:]]*" "$file" 2>/dev/null; then
    sed -i -E "s|^[[:space:]]*${key}:[[:space:]]*.*$|${key}: ${value}|g" "$file"
  else
    # 追加前保证有换行
    if [ "$(tail -c 1 "$file" 2>/dev/null || true)" != "" ]; then
      printf "\n" >>"$file"
    fi
    printf "%s: %s\n" "$key" "$value" >>"$file"
  fi
}

# 强制写入 secret 到配置文件
force_write_secret() {
  local file="$1"
  local secret="${SECRET:-}"
  [ -f "$file" ] || return 0
  [ -n "$secret" ] || return 0

  if grep -qE '^[[:space:]]*secret:' "$file"; then
    sed -i -E "s|^[[:space:]]*secret:.*$|secret: ${secret}|g" "$file"
  else
    printf "\nsecret: %s\n" "$secret" >> "$file"
  fi
}

# =========================
# 配置生成
# =========================

# 应用 TUN 配置
apply_tun_config() {
  local config_path="$1"
  local enable="${CLASH_TUN_ENABLE:-false}"
  [ "$enable" != "true" ] && return 0

  local stack="${CLASH_TUN_STACK:-system}"
  local auto_route="${CLASH_TUN_AUTO_ROUTE:-true}"
  local auto_redirect="${CLASH_TUN_AUTO_REDIRECT:-false}"
  local strict_route="${CLASH_TUN_STRICT_ROUTE:-false}"
  local device="${CLASH_TUN_DEVICE:-}"
  local mtu="${CLASH_TUN_MTU:-}"
  local dns_hijack="${CLASH_TUN_DNS_HIJACK:-}"

  {
    echo ""
    echo "tun:"
    echo "  enable: true"
    echo "  stack: ${stack}"
    echo "  auto-route: ${auto_route}"
    echo "  auto-redirect: ${auto_redirect}"
    echo "  strict-route: ${strict_route}"
    [ -n "$device" ] && echo "  device: ${device}"
    [ -n "$mtu" ] && echo "  mtu: ${mtu}"
    if [ -n "$dns_hijack" ]; then
      echo "  dns-hijack:"
      IFS=',' read -r -a hijacks <<< "$dns_hijack"
      for item in "${hijacks[@]}"; do
        local trimmed
        trimmed=$(trim_value "$item")
        [ -n "$trimmed" ] && echo "    - ${trimmed}"
      done
    fi
  } >> "$config_path"
}

# 应用 Mixin 配置
apply_mixin_config() {
  local config_path="$1"
  local base_dir="${2:-${SERVER_DIR}}"
  local mixin_dir="${CLASH_MIXIN_DIR:-$base_dir/volumes/mixin.d}"
  local mixin_paths=()

  [ -n "${CLASH_MIXIN_PATHS:-}" ] && IFS=',' read -r -a mixin_paths <<< "$CLASH_MIXIN_PATHS"

  if [ -d "$mixin_dir" ]; then
    while IFS= read -r -d '' file; do
      mixin_paths+=("$file")
    done < <(find "$mixin_dir" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 | sort -z)
  fi

  for path in "${mixin_paths[@]}"; do
    local trimmed
    trimmed=$(trim_value "$path")
    [ -z "$trimmed" ] && continue
    [ "${trimmed:0:1}" != "/" ] && trimmed="$base_dir/$trimmed"
    if [ -f "$trimmed" ]; then
      {
        echo ""
        echo "# ---- mixin: ${trimmed} ----"
        cat "$trimmed"
      } >> "$config_path"
    else
      echo "[WARN] Mixin file not found: $trimmed" >&2
    fi
  done
}

# 检查是否是完整 Clash 配置
is_full_clash_config() {
  local file="$1"
  [ -s "$file" ] || return 1
  grep -qE '^(proxies:|proxy-providers:|mixed-port:|port:|dns:)' "$file"
}
