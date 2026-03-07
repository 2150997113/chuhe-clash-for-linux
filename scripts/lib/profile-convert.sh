#!/usr/bin/env bash
set -euo pipefail

# 作用：
# - 将订阅内容转换成 Clash Meta / Mihomo 可用的完整 YAML 配置
# - 默认使用 subconverter HTTP /sub 接口（最稳：用 -G + --data-urlencode）
# - 失败则跳过，不影响主流程
#
# 输入/输出约定：
# - IN_FILE：原订阅（默认 temp/clash.yaml）
# - OUT_FILE：转换后的配置（默认 temp/clash_config.yaml）
#
# 设计原则：
# - 绝不 exit 1（失败只 warn 并 exit 0）
# - 已是完整 Clash 配置则直接 copy
# - 没有 CLASH_URL（原始订阅 URL）则不转换（subconverter 最稳是 url=...）

SERVER_DIR="${SERVER_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TEMP_DIR="${TEMP_DIR:-$SERVER_DIR/temp}"

mkdir -p "$TEMP_DIR"

IN_FILE="${IN_FILE:-$TEMP_DIR/clash.yaml}"
OUT_FILE="${OUT_FILE:-$TEMP_DIR/clash_config.yaml}"

# "更先进"的默认：Clash Meta / Mihomo
SUB_TARGET="${SUB_TARGET:-clashmeta}"   # 推荐 clashmeta（兼容面最广）
SUB_URL="${CLASH_URL:-}"               # 原始订阅 URL（.env 里 export CLASH_URL=...）

# 0) 输入不存在就跳过
if [ ! -s "$IN_FILE" ]; then
  echo "[WARN] no input file: $IN_FILE"
  exit 0
fi

# 1) 如果看起来已经是完整 Clash 配置，就直接用，不转换
#    （包含 proxies / proxy-providers / rules / port 等任一关键词即可认为是完整配置）
if grep -qE '^(proxies:|proxy-providers:|mixed-port:|port:|rules:|dns:)' "$IN_FILE"; then
  cp -f "$IN_FILE" "$OUT_FILE"
  echo "[OK] input already looks like a Clash config -> $OUT_FILE"
  exit 0
fi

# 2) subconverter 不可用就跳过
if [ "${SUBCONVERTER_READY:-false}" != "true" ] || [ -z "${SUBCONVERTER_URL:-}" ]; then
  echo "[WARN] subconverter not ready, skip conversion"
  exit 0
fi

# 3) 没有原始 URL 就不转（subconverter 最稳是 url=... 拉取）
if [ -z "${SUB_URL:-}" ]; then
  echo "[WARN] CLASH_URL empty, cannot convert via /sub, skip"
  exit 0
fi

# 4) 调用 subconverter：用 -G + --data-urlencode，避免 url 参数里含 ? & 导致 400
#    注意：SUB_URL 必须是原始订阅 URL（例如 https://.../subscribe?token=xxx）
TMP_OUT="${OUT_FILE}.tmp"
rm -f "$TMP_OUT" 2>/dev/null || true

set +e
curl -fsSLG "${SUBCONVERTER_URL}/sub" \
  --data-urlencode "target=${SUB_TARGET}" \
  --data-urlencode "url=${SUB_URL}" \
  -o "${TMP_OUT}"
rc=$?
set -e

if [ "$rc" -ne 0 ] || [ ! -s "$TMP_OUT" ]; then
  echo "[WARN] convert failed (rc=${rc}), skip"
  rm -f "$TMP_OUT" 2>/dev/null || true
  exit 0
fi

mv -f "$TMP_OUT" "$OUT_FILE"
echo "[OK] converted via subconverter -> ${OUT_FILE} (target=${SUB_TARGET})"

true
