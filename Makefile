# Makefile for clash-for-linux
# 项目命令统一入口

SHELL := /bin/bash
CMD := scripts/cmd

.PHONY: install uninstall start stop restart update status env \
        sub-add sub-list sub-use sub-update help

# ==================== 服务生命周期 ====================

install:
	@sudo bash $(CMD)/service-install.sh

uninstall:
	@sudo bash $(CMD)/service-uninstall.sh

start:
	@bash $(CMD)/service-start.sh

stop:
	@bash $(CMD)/service-stop.sh

restart:
	@bash $(CMD)/service-restart.sh

update:
	@bash $(CMD)/subscription-update.sh

status:
	@./clashctl status

env:
	@SERVER_DIR="$$(cd "$(dirname "$$0")" && pwd)"; \
	if [ ! -f /etc/profile.d/clash-for-linux.sh ]; then \
		echo "[INFO] 生成 /etc/profile.d/clash-for-linux.sh ..."; \
		source "$$SERVER_DIR/scripts/lib/systemd-utils.sh" && install_profiled "$$SERVER_DIR"; \
		echo "[OK] 文件已生成"; \
	else \
		echo "[OK] /etc/profile.d/clash-for-linux.sh 已存在"; \
	fi
	@echo ""
	@echo "请在当前 shell 执行以下命令使别名生效:"
	@echo "  source /etc/profile.d/clash-for-linux.sh"
	@echo ""
	@echo "可用命令: proxy-on / proxy-down / proxy_on / proxy_down"

# ==================== 订阅管理 ====================

sub-add:
	@read -p "订阅名称: " name; \
	read -p "订阅地址: " url; \
	./clashctl sub add "$$name" "$$url"

sub-list:
	@./clashctl sub list

sub-use:
	@read -p "订阅名称: " name; \
	./clashctl sub use "$$name"

sub-update:
	@./clashctl sub update

# ==================== 帮助 ====================

help:
	@echo "clash-for-linux 命令手册"
	@echo ""
	@echo "服务生命周期:"
	@echo "  make install      安装服务"
	@echo "  make uninstall    卸载服务"
	@echo "  make start        启动服务"
	@echo "  make stop         停止服务"
	@echo "  make restart      重启服务"
	@echo "  make update       更新订阅"
	@echo "  make status       查看状态"
	@echo ""
	@echo "订阅管理:"
	@echo "  make sub-add      添加订阅"
	@echo "  make sub-list     列出订阅"
	@echo "  make sub-use      切换订阅"
	@echo "  make sub-update   更新订阅"
	@echo ""
	@echo "详细命令: ./clashctl --help"
