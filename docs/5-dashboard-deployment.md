# Dashboard 部署方式

本文档详细描述 Dashboard 的部署架构与实现方式。

---

## 1. 部署架构概述

Dashboard 采用 **预编译静态文件 + Clash 内置服务** 的部署方式：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              部署架构                                        │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                        传统 Web 应用部署                                     │
│                                                                              │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                    │
│   │  Nginx      │    │  Node.js    │    │  Apache     │                    │
│   │  反向代理   │    │  应用服务器  │    │  Web 服务器 │                    │
│   └─────────────┘    └─────────────┘    └─────────────┘                    │
│          │                  │                  │                            │
│          └──────────────────┼──────────────────┘                            │
│                             │                                               │
│                    需要独立进程                                              │
│                    需要额外配置                                              │
│                    需要额外端口                                              │
└─────────────────────────────────────────────────────────────────────────────┘

                              VS

┌─────────────────────────────────────────────────────────────────────────────┐
│                     clash-for-linux 部署方式                                │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │                      Clash 内核 (单一进程)                           │  │
│   │                                                                      │  │
│   │   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐            │  │
│   │   │ 代理核心    │    │ HTTP Server │    │ RESTful API │            │  │
│   │   │ (SOCKS/HTTP)│    │ (静态文件)  │    │ (管理接口)  │            │  │
│   │   └─────────────┘    └─────────────┘    └─────────────┘            │  │
│   │         │                  │                  │                     │  │
│   │         │                  │                  │                     │  │
│   │   ┌─────┴─────┐      ┌─────┴─────┐      ┌─────┴─────┐              │  │
│   │   │ :7890    │      │ /ui/*     │      │ /api/*    │              │  │
│   │   │ :7891    │      │ 静态文件   │      │ JSON API  │              │  │
│   │   │ 代理端口  │      │ Dashboard │      │ 管理接口  │              │  │
│   │   └───────────┘      └───────────┘      └───────────┘              │  │
│   │                                                                      │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│   ✓ 单一进程，无需额外服务                                                   │
│   ✓ 无需独立 Web 服务器                                                      │
│   ✓ 复用 Clash API 端口                                                     │
│   ✓ 零额外配置                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. 部署方式详解

### 2.1 静态文件预编译

Dashboard 源码使用 Nuxt.js 框架开发，已预编译为纯静态文件：

```
dashboard/public/
├── index.html              # 入口 HTML
├── config.js               # 配置文件
├── favicon.ico             # 网站图标
├── favicon.svg
├── pwa-*.png               # PWA 图标
├── apple-touch-icon.png
├── 200.html                # SPA 回退页面
├── 404.html                # 404 页面
└── _nuxt/                  # 预编译的 JS/CSS
    ├── B7rlnwkb.js         # 入口 JS
    ├── entry.A2e2demF.css  # 入口 CSS
    ├── *.js                # 按需加载的模块
    └── *.woff2             # 字体文件
```

**特点**：
- 无需 Node.js 运行时
- 无需服务器端渲染
- 可直接被静态文件服务器托管

### 2.2 Clash 内置 HTTP Server

Clash 内核内置了一个轻量级 HTTP Server：

```yaml
# config.yaml
external-controller: 127.0.0.1:9090    # API 监听地址
external-ui: /path/to/ui               # 静态文件目录
secret: xxx                            # 认证密钥
```

**服务能力**：

| 路径 | 服务类型 | 说明 |
|------|----------|------|
| `/ui/*` | 静态文件服务 | 提供 Dashboard 文件 |
| `/api/*` | RESTful API | 提供管理接口 |
| `/logs` | WebSocket | 实时日志流 |
| `/traffic` | WebSocket | 实时流量统计 |
| `/connections` | WebSocket | 实时连接监控 |

### 2.3 软链接集成

通过软链接将 Dashboard 文件关联到配置路径：

```bash
# 源文件目录
Dashboard_Src="/opt/clash-for-linux/dashboard/public"

# 目标链接路径
Dashboard_Link="/opt/clash-for-linux/conf/ui"

# 创建软链接
ln -sfn "$Dashboard_Src" "$Dashboard_Link"
```

**目录结构**：

```
/opt/clash-for-linux/
├── dashboard/
│   └── public/              # 实际的静态文件
│       ├── index.html
│       └── _nuxt/
│
├── conf/
│   ├── config.yaml          # Clash 配置
│   └── ui -> ../dashboard/public/   # 软链接
│
└── .env                     # 环境变量
```

---

## 3. 部署流程

### 3.1 完整部署流程图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              部署流程                                        │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────┐
│ 1. 项目克隆 │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ git clone https://github.com/wnlen/clash-for-linux.git                      │
│                                                                              │
│ 下载内容:                                                                    │
│ ├── bin/clash-linux-*        # Clash 内核                                   │
│ ├── dashboard/public/        # Dashboard 静态文件（已预编译）               │
│ ├── scripts/                 # 管理脚本                                     │
│ ├── conf/                    # 配置目录                                     │
│ └── .env                     # 环境变量模板                                 │
└─────────────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────┐
│ 2. 安装脚本 │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ sudo bash install.sh                                                        │
│                                                                              │
│ 执行操作:                                                                    │
│ ├── 同步文件到 /opt/clash-for-linux/                                        │
│ ├── 设置脚本执行权限                                                         │
│ ├── 创建 conf/, logs/, temp/ 目录                                           │
│ └── 安装 clashctl 到 /usr/local/bin                                         │
└─────────────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────┐
│ 3. 服务启动 │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ start.sh 执行 (由 systemd 或手动触发)                                        │
│                                                                              │
│ Dashboard 相关操作:                                                          │
│ │                                                                           │
│ │  ┌─────────────────────────────────────────────────────────────────────┐ │
│ │  │ # 1. 创建软链接                                                      │ │
│ │  │ Dashboard_Src="$Server_Dir/dashboard/public"                        │ │
│ │  │ Dashboard_Link="$Conf_Dir/ui"                                       │ │
│ │  │ ln -sfn "$Dashboard_Src" "$Dashboard_Link"                          │ │
│ │  └─────────────────────────────────────────────────────────────────────┘ │
│ │                                                                           │
│ │  ┌─────────────────────────────────────────────────────────────────────┐ │
│ │  │ # 2. 写入配置文件                                                    │ │
│ │  │ upsert_yaml_kv "$CONFIG_FILE" "external-ui" "$Dashboard_Link"       │ │
│ │  │ upsert_yaml_kv "$CONFIG_FILE" "external-controller" "127.0.0.1:9090"│ │
│ │  │ force_write_secret "$CONFIG_FILE"                                   │ │
│ │  └─────────────────────────────────────────────────────────────────────┘ │
│ │                                                                           │
│ │  ┌─────────────────────────────────────────────────────────────────────┐ │
│ │  │ # 3. 启动 Clash 内核                                                 │ │
│ │  │ exec "$Clash_Bin" -f "$CONFIG_FILE" -d "$RUNTIME_DIR"               │ │
│ │  └─────────────────────────────────────────────────────────────────────┘ │
│ │                                                                           │
└─────────────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────┐
│ 4. 服务就绪 │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ Clash 内核运行中                                                             │
│                                                                              │
│ 监听端口:                                                                    │
│ ├── 7890 (HTTP/SOCKS5 混合端口)                                             │
│ ├── 7891 (SOCKS5 端口，可选)                                                │
│ ├── 7892 (透明代理端口，可选)                                               │
│ └── 9090 (external-controller)                                              │
│                                                                              │
│ 服务内容:                                                                    │
│ ├── /ui/*    → Dashboard 静态文件                                           │
│ ├── /api/*   → RESTful API                                                  │
│ └── /logs, /traffic, /connections → WebSocket                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 关键代码片段

**start.sh 中的 Dashboard 集成**：

```bash
#!/bin/bash
set -euo pipefail

# 目录定义
Server_Dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
Conf_Dir="$Server_Dir/conf"
Temp_Dir="$Server_Dir/temp"

# Dashboard 源目录
Dashboard_Src="$Server_Dir/dashboard/public"

# === 步骤1: 创建软链接 ===
if [ "${SYSTEMD_MODE:-false}" = "true" ] && [ "$(id -u)" -ne 0 ]; then
    # 非 root 模式: 链接到 temp 目录
    Dashboard_Link="$Temp_Dir/ui"
else
    # root 模式: 链接到 conf 目录
    Dashboard_Link="$Conf_Dir/ui"
fi

if [ -d "$Dashboard_Src" ]; then
    ln -sfn "$Dashboard_Src" "$Dashboard_Link"
else
    echo "[WARN] Dashboard source not found: $Dashboard_Src"
fi

# === 步骤2: 写入配置 ===
# external-ui
if grep -qE '^[[:space:]]*external-ui:' "$CONFIG_FILE"; then
    sed -i -E "s|^[[:space:]]*external-ui:.*$|external-ui: ${Dashboard_Link}|g" "$CONFIG_FILE"
else
    echo "external-ui: ${Dashboard_Link}" >> "$CONFIG_FILE"
fi

# external-controller
if grep -qE '^[[:space:]]*external-controller:' "$CONFIG_FILE"; then
    sed -i -E "s|^[[:space:]]*external-controller:.*$|external-controller: ${EXTERNAL_CONTROLLER}|g" "$CONFIG_FILE"
else
    echo "external-controller: ${EXTERNAL_CONTROLLER}" >> "$CONFIG_FILE"
fi

# secret
echo "secret: ${Secret}" >> "$CONFIG_FILE"

# === 步骤3: 启动 Clash ===
exec "$Clash_Bin" -f "$CONFIG_FILE" -d "$RUNTIME_DIR"
```

---

## 4. 访问方式

### 4.1 本机访问

```bash
# 直接在服务器浏览器访问
http://127.0.0.1:9090/ui
```

### 4.2 SSH 端口转发（推荐）

```bash
# 在本地终端执行
ssh -N -L 9090:127.0.0.1:9090 user@server

# 然后在本地浏览器访问
http://127.0.0.1:9090/ui
```

### 4.3 公网访问（不推荐）

```bash
# 修改 .env
export EXTERNAL_CONTROLLER='0.0.0.0:9090'
export CLASH_SECRET='your-strong-secret'

# 重启服务
clashctl restart

# 浏览器访问
http://your-server:9090/ui
```

---

## 5. 与传统方式对比

### 5.1 对比表

| 对比项 | 传统部署 | clash-for-linux 部署 |
|--------|----------|---------------------|
| Web 服务器 | Nginx/Node.js/Apache | Clash 内置 |
| 进程数量 | 2+ (Clash + Web服务器) | 1 (仅 Clash) |
| 端口占用 | 多个端口 | 单一端口复用 |
| 配置复杂度 | 高（需配置反向代理） | 低（仅需一行配置） |
| 内存占用 | 高 | 低 |
| 维护成本 | 高 | 低 |

### 5.2 架构对比图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           传统部署架构                                        │
└─────────────────────────────────────────────────────────────────────────────┘

     浏览器
        │
        │ HTTP :80/:443
        ▼
┌───────────────┐
│    Nginx      │  ← 需要配置反向代理
│  反向代理     │
└───────┬───────┘
        │
        │ proxy_pass
        ▼
┌───────────────┐        ┌───────────────┐
│   Node.js     │        │    Clash      │
│  (Dashboard)  │───────>│   (代理)      │
│   :3000       │  API   │   :9090       │
└───────────────┘        └───────────────┘

总进程: 3 (Nginx + Node.js + Clash)
总端口: 3 (80/443 + 3000 + 9090)


┌─────────────────────────────────────────────────────────────────────────────┐
│                      clash-for-linux 部署架构                                │
└─────────────────────────────────────────────────────────────────────────────┘

     浏览器
        │
        │ HTTP :9090/ui
        ▼
┌───────────────────────────────────────────────┐
│                  Clash 内核                    │
│                                               │
│  ┌─────────────┐    ┌─────────────────────┐  │
│  │ HTTP Server │    │    Proxy Core       │  │
│  │  /ui/*      │    │    :7890/:7891      │  │
│  │  /api/*     │    │                     │  │
│  └─────────────┘    └─────────────────────┘  │
│                                               │
└───────────────────────────────────────────────┘

总进程: 1 (仅 Clash)
总端口: 2 (9090 API + 7890 代理)
```

---

## 6. 更新 Dashboard

### 6.1 手动更新

```bash
# 下载最新版本
cd /tmp
git clone --depth 1 https://github.com/MetaCubeX/metacubexd.git
cd metacubexd

# 构建（需要 Node.js 18+）
pnpm install
pnpm build

# 部署
rm -rf /opt/clash-for-linux/dashboard/public/*
cp -r dist/* /opt/clash-for-linux/dashboard/public/

# 无需重启，刷新浏览器即可
```

### 6.2 使用预编译版本

```bash
# 下载预编译版本
cd /tmp
wget https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.zip

# 解压部署
unzip compressed-dist.zip -d /opt/clash-for-linux/dashboard/public/
```

---

## 7. 故障排查

### 7.1 Dashboard 无法访问

```bash
# 1. 检查 Clash 是否运行
ps aux | grep clash

# 2. 检查端口是否监听
ss -tlnp | grep 9090

# 3. 测试 API 是否响应
curl http://127.0.0.1:9090/api/version

# 4. 检查软链接是否存在
ls -la /opt/clash-for-linux/conf/ui

# 5. 检查配置
grep "external-ui\|external-controller" /opt/clash-for-linux/conf/config.yaml
```

### 7.2 SAFE_PATH 错误

Mihomo 内核有安全路径限制：

```bash
# 查看日志
journalctl -u clash-for-linux.service -n 50

# 如果看到 SAFE_PATH 错误，检查路径
# start.sh 会自动处理，将 UI 复制到允许的目录
```

### 7.3 认证失败

```bash
# 获取当前 secret
grep "secret:" /opt/clash-for-linux/conf/config.yaml

# 使用正确的 secret 访问
curl -H "Authorization: Bearer <secret>" http://127.0.0.1:9090/api/proxies
```

---

## 8. 设计优势总结

| 优势 | 说明 |
|------|------|
| **零依赖** | 无需 Nginx、Node.js 等外部服务 |
| **单进程** | Clash 内核同时提供代理和 Web 服务 |
| **低资源** | 内存占用低，适合服务器/嵌入式设备 |
| **易维护** | 静态文件，无需关注运行时环境 |
| **安全** | 默认仅本机访问，Secret 认证 |
| **简单** | 一行配置即可启用 |
