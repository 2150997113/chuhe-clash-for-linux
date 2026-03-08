#!/bin/bash
set -euo pipefail

#################### 基本变量 ####################

# 获取项目根目录（从 scripts/cmd/ 向上两级）
SERVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SERVICE_NAME="clash-for-linux"

SERVICE_USER="root"
SERVICE_GROUP="root"

Unit_Path="/etc/systemd/system/${SERVICE_NAME}.service"
PID_FILE="$SERVER_DIR/temp/clash.pid"

#################### 权限检查 ####################

if [ "$(id -u)" -ne 0 ]; then
  echo -e "\033[31m[ERROR] 需要 root 权限来安装 systemd 单元\033[0m"
  exit 1
fi

#################### 目录初始化 ####################

install -d -m 0755 \
  "$SERVER_DIR/conf" \
  "$SERVER_DIR/logs" \
  "$SERVER_DIR/temp"

#################### 生成 systemd Unit ####################

cat >"$Unit_Path"<<EOF
[Unit]
Description=Clash for Linux
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$SERVER_DIR

# 启动 / 停止
ExecStart=/bin/bash $SERVER_DIR/scripts/cmd/service-start.sh
ExecStop=/bin/bash $SERVER_DIR/scripts/cmd/service-stop.sh

# 失败策略
Restart=on-failure
RestartSec=5
TimeoutStartSec=120
TimeoutStopSec=30

# 环境变量
Environment=SYSTEMD_MODE=true
Environment=CLASH_ENV_FILE=$SERVER_DIR/temp/clash-for-linux.sh
Environment=CLASH_HOME=$SERVER_DIR

[Install]
WantedBy=multi-user.target
EOF

#################### 刷新 systemd ####################

systemctl daemon-reload
