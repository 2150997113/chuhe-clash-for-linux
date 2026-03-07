#!/bin/bash
# clash-for-linux 命令 wrapper
# 支持: m up <name>, m del <name>, m add <name> url=xxx, m list
# 支持: m proxy up, m proxy down
# 以及所有标准 make 命令

set -e

# 解析项目目录（支持 symlink）
resolve_project_dir() {
  local script_path="${BASH_SOURCE[0]}"

  # 如果是 symlink，解析到真实路径
  if [ -L "$script_path" ]; then
    script_path="$(readlink -f "$script_path")"
  fi

  cd "$(dirname "$script_path")" && pwd
}

PROJECT_DIR="$(resolve_project_dir)"

# 订阅管理快捷命令
case "${1:-}" in
  up)
    name="${2:-}"
    if [ -z "$name" ]; then
      echo "[ERROR] 用法: m up <name>" >&2
      exit 1
    fi
    exec "$PROJECT_DIR/clashctl" sub use "$name"
    ;;
  del)
    name="${2:-}"
    if [ -z "$name" ]; then
      echo "[ERROR] 用法: m del <name>" >&2
      exit 1
    fi
    exec "$PROJECT_DIR/clashctl" sub del "$name"
    ;;
  add)
    name="${2:-}"
    if [ -z "$name" ]; then
      echo "[ERROR] 用法: m add <name> url=xxx [headers=xxx]" >&2
      exit 1
    fi
    url="${3:-}"
    if [ -z "$url" ]; then
      echo "[ERROR] 用法: m add <name> url=xxx [headers=xxx]" >&2
      exit 1
    fi
    # 去掉 url= 前缀
    url="${url#url=}"
    headers="${4:-}"
    headers="${headers#headers=}"
    exec "$PROJECT_DIR/clashctl" sub add "$name" "$url" "$headers"
    ;;
  list)
    exec "$PROJECT_DIR/clashctl" sub list
    ;;
  proxy)
    action="${2:-}"
    case "$action" in
      up)
        source /etc/profile.d/clash-for-linux.sh && proxy_on
        exit 0
        ;;
      down)
        source /etc/profile.d/clash-for-linux.sh && proxy_down
        exit 0
        ;;
      *)
        echo "[ERROR] 用法: m proxy up|down" >&2
        exit 1
        ;;
    esac
    ;;
esac

# 其他命令透传给 make
exec /usr/bin/make -C "$PROJECT_DIR" "$@"
