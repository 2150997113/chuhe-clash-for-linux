# Makefile for clash-for-linux
# 项目命令统一入口

SHELL := /bin/bash
CMD := scripts/cmd

# 允许任意参数作为目标（避免 make 报错）
.PHONY: install uninstall start stop down restart update status test env help list
.DEFAULT_GOAL := help

# ==================== 服务生命周期 ====================

install:
	@sudo bash $(CMD)/service-install.sh

uninstall:
	@sudo bash $(CMD)/service-uninstall.sh

start:
	@bash $(CMD)/service-start.sh

stop:
	@bash $(CMD)/service-stop.sh

down: stop

restart:
	@bash $(CMD)/service-restart.sh

update:
	@bash $(CMD)/subscription-update.sh

status:
	@./clashctl status

test:
	@source /etc/profile.d/clash-for-linux.sh && proxy_on && \
	curl -s --max-time 5 https://www.google.com -o /dev/null && \
	echo "[OK] Google 可访问" || echo "[FAIL] 代理不可用"

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

list:
	@./clashctl sub list

up:
	@args="$(filter-out $@,$(MAKECMDGOALS))"; \
	if [ -z "$$args" ] || echo "$$args" | grep -qE '^(up|down|proxy)$$'; then \
		echo "[ERROR] 用法: make up <name>"; \
		exit 1; \
	fi; \
	./clashctl sub use "$$args"

del:
	@args="$(filter-out $@,$(MAKECMDGOALS))"; \
	if [ -z "$$args" ] || echo "$$args" | grep -qE '^(up|down|proxy)$$'; then \
		echo "[ERROR] 用法: make del <name>"; \
		exit 1; \
	fi; \
	./clashctl sub del "$$args"

add:
	@args="$(filter-out $@,$(MAKECMDGOALS))"; \
	if [ -z "$$args" ] || [ -z "$(url)" ] || echo "$$args" | grep -qE '^(up|down|proxy)$$'; then \
		echo "[ERROR] 用法: make add <name> url=xxx [headers=xxx]"; \
		exit 1; \
	fi; \
	./clashctl sub add "$$args" "$(url)" "$(headers:-)"

proxy-up:
	@source /etc/profile.d/clash-for-linux.sh && proxy_on

proxy-down:
	@source /etc/profile.d/clash-for-linux.sh && proxy_down

# 防止 make 对参数报错
%:
	@:

# ==================== 帮助 ====================

help:
	@echo "clash-for-linux 命令手册"
	@echo ""
	@echo "服务生命周期:"
	@echo "  make install      安装服务"
	@echo "  make uninstall    卸载服务"
	@echo "  make start        启动服务"
	@echo "  make stop/down    停止服务"
	@echo "  make restart      重启服务"
	@echo "  make update       更新订阅"
	@echo "  make status       查看状态"
	@echo "  make test         测试代理连通性"
	@echo ""
	@echo "代理快捷命令:"
	@echo "  make proxy-up     开启代理"
	@echo "  make proxy-down   关闭代理"
	@echo "  m proxy up        开启代理 (wrapper)"
	@echo "  m proxy down      关闭代理 (wrapper)"
	@echo ""
	@echo "订阅管理:"
	@echo "  make list         列出订阅"
	@echo "  make up <name>    切换订阅"
	@echo "  make del <name>   删除订阅"
	@echo "  make add <name> url=xxx  添加订阅"
	@echo ""
	@echo "详细命令: ./clashctl --help"
