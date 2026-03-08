# justfile for clash-for-linux
# 项目命令统一入口

CMD := "scripts/cmd"

# 默认：列出所有命令
default:
    just --list

# 检查依赖（make 和 just）
check:
    @bash check-deps.sh

# ==================== 服务管理 ====================

# 安装服务
install:
    sudo bash {{CMD}}/service-install.sh

# 卸载服务
uninstall:
    sudo bash {{CMD}}/service-uninstall.sh

# Clash 服务控制: just clash up / just clash down
clash action:
    #!/usr/bin/env bash
    if [ "{{action}}" = "up" ]; then
        bash {{CMD}}/service-start.sh
    elif [ "{{action}}" = "down" ]; then
        bash {{CMD}}/service-stop.sh
    else
        echo "[ERROR] 用法: just clash up|down" >&2
        exit 1
    fi

# 重启服务
restart:
    bash {{CMD}}/service-restart.sh

# 更新订阅
update:
    bash {{CMD}}/subscription-update.sh

# 查看状态（服务状态 + 代理状态）
status:
    #!/usr/bin/env bash
    echo "▶ 服务状态"
    echo "────────────────────────────────────────"
    ./clashctl status
    echo ""
    echo "▶ 代理状态"
    echo "────────────────────────────────────────"
    if [ -n "${http_proxy:-}" ] || [ -n "${HTTP_PROXY:-}" ]; then
        echo "[OK] 代理已开启: ${http_proxy:-${HTTP_PROXY:-}}"
    else
        echo "[OFF] 代理未开启"
        echo "      执行 'just up' 开启代理"
    fi

# 查看日志
logs:
    ./clashctl status

# 测试代理连通性
test:
    #!/usr/bin/env bash
    source /etc/profile.d/clash-for-linux.sh && proxy_on && \
    curl -s --max-time 5 https://www.google.com -o /dev/null && \
    echo "[OK] Google 可访问" || echo "[FAIL] 代理不可用"

# ==================== 代理控制 ====================

# 启用代理（等效于 proxy_on）
up:
    @bash -c 'source /etc/profile.d/clash-for-linux.sh && proxy_on'

# 关闭代理（等效于 proxy_down）
down:
    @bash -c 'source /etc/profile.d/clash-for-linux.sh && proxy_down'

# ==================== 订阅管理 ====================

# 列出订阅
list:
    ./clashctl sub list

# 切换订阅
use name:
    ./clashctl sub use {{name}}

# 删除订阅
del name:
    ./clashctl sub del {{name}}

# 添加订阅 (url 或 local:/path/to/config.yaml)
add name url:
    ./clashctl sub add {{name}} {{url}}
