# Dashboard 设计文档

本文档描述 clash-for-linux 中 Dashboard（管理面板）的设计与实现。

---

## 1. 功能概述

Dashboard 是 Clash 的 Web 管理界面，提供以下核心功能：

| 功能 | 说明 |
|------|------|
| 节点管理 | 查看、选择、测试代理节点 |
| 规则查看 | 查看分流规则、匹配情况 |
| 连接管理 | 查看实时连接、关闭连接 |
| 日志查看 | 实时查看 Clash 运行日志 |
| 配置管理 | 切换配置、更新订阅 |
| 流量统计 | 查看节点流量使用情况 |

---

## 2. 架构设计

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              用户浏览器                                       │
│                     http://127.0.0.1:9090/ui                                 │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      │ HTTP 请求
                                      │
┌─────────────────────────────────────▼───────────────────────────────────────┐
│                           Clash 内核 (Mihomo)                                │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      HTTP Server (内置)                              │   │
│  │                                                                      │   │
│  │   /ui/*      ───────> 静态文件服务 (external-ui)                    │   │
│  │   /api/*     ───────> RESTful API (external-controller)             │   │
│  │   /logs      ───────> WebSocket 日志流                              │   │
│  │   /traffic   ───────> WebSocket 流量统计                            │   │
│  │   /connections ────> WebSocket 连接监控                             │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      配置文件 (config.yaml)                          │   │
│  │                                                                      │   │
│  │   external-controller: 127.0.0.1:9090   # API 监听地址              │   │
│  │   external-ui: /opt/clash-for-linux/conf/ui  # UI 文件路径          │   │
│  │   secret: xxxxxx                        # API 认证密钥              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                      ▲
                                      │ 文件系统
                                      │
┌─────────────────────────────────────┴───────────────────────────────────────┐
│                     dashboard/public (静态文件)                              │
│                                                                              │
│   index.html          # 入口 HTML                                           │
│   config.js           # 配置文件                                            │
│   _nuxt/*.js          # 预编译的 JS/CSS 资源                                │
│   pwa-*.png           # PWA 图标                                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 组件说明

| 组件 | 说明 |
|------|------|
| **Dashboard (MetaCubeXD)** | Nuxt.js 预编译的静态 Web 应用 |
| **Clash HTTP Server** | 内置于 Clash 内核，提供静态文件服务和 API |
| **external-controller** | RESTful API 端点，用于管理操作 |
| **external-ui** | 静态文件目录，Dashboard 文件存放位置 |
| **secret** | API 认证密钥，防止未授权访问 |

### 2.3 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| 前端框架 | Nuxt.js 3 | Vue.js 服务端渲染框架（已预编译为静态） |
| UI 组件 | 无外部依赖 | 自包含，无需安装 |
| 通信协议 | HTTP + WebSocket | RESTful API + 实时数据流 |
| 构建产物 | 静态 HTML/JS/CSS | 无需 Node.js 运行时 |

---

## 3. 工作原理

### 3.1 请求流程

```
┌──────────┐      ┌──────────────────────────────────────────────────────┐
│  浏览器  │      │                    Clash 内核                         │
└────┬─────┘      └──────────────────────────────────────────────────────┘
     │
     │  GET /ui/
     │─────────────────────────────────────────────────────────────────────>
     │
     │                                              ┌─────────────────────┐
     │                                              │ 读取 external-ui    │
     │                                              │ 目录下的 index.html │
     │                                              └──────────┬──────────┘
     │                                                         │
     │  返回 index.html                                        │
     │<─────────────────────────────────────────────────────────
     │
     │  GET /ui/_nuxt/xxx.js
     │─────────────────────────────────────────────────────────────────────>
     │
     │  返回 JS 文件
     │<─────────────────────────────────────────────────────────────────────
     │
     │  ┌─────────────────────────────────────────────────────────────────┐
     │  │ Dashboard JS 初始化                                              │
     │  │ - 读取 config.js 获取配置                                        │
     │  │ - 连接 external-controller API                                  │
     │  │ - 使用 secret 进行认证                                           │
     │  └─────────────────────────────────────────────────────────────────┘
     │
     │  GET /api/proxies (Authorization: Bearer <secret>)
     │─────────────────────────────────────────────────────────────────────>
     │
     │  返回代理节点列表 JSON
     │<─────────────────────────────────────────────────────────────────────
     │
     │  WebSocket /logs
     │─────────────────────────────────────────────────────────────────────>
     │
     │  实时推送日志消息
     │<═════════════════════════════════════════════════════════════════════
     │
     ▼
```

### 3.2 API 交互

Dashboard 通过 Clash 的 RESTful API 进行管理操作：

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Clash RESTful API                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  GET    /api/proxies              # 获取所有代理                           │
│  PUT    /api/proxies/{name}       # 切换代理选择                           │
│  GET    /api/proxies/{name}/delay # 测试代理延迟                           │
│                                                                             │
│  GET    /api/rules                # 获取规则列表                           │
│  GET    /api/connections          # 获取连接列表                           │
│  DELETE /api/connections/{id}     # 关闭指定连接                           │
│  DELETE /api/connections          # 关闭所有连接                           │
│                                                                             │
│  GET    /api/configs              # 获取配置信息                           │
│  PATCH  /api/configs              # 更新配置                               │
│  PUT    /api/configs              # 重载配置                               │
│                                                                             │
│  GET    /api/logs                 # WebSocket 日志流                       │
│  GET    /api/traffic              # WebSocket 流量统计                     │
│  GET    /api/version              # 获取版本信息                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.3 认证机制

所有 API 请求需要通过 `secret` 认证：

```http
GET /api/proxies HTTP/1.1
Host: 127.0.0.1:9090
Authorization: Bearer <secret>
```

或通过 URL 参数：

```
GET /api/proxies?secret=<secret>
```

---

## 4. 文件集成

### 4.1 目录结构

```
clash-for-linux/
├── dashboard/
│   └── public/                    # Dashboard 静态文件
│       ├── index.html             # 入口 HTML
│       ├── config.js              # 配置文件
│       ├── favicon.ico
│       ├── favicon.svg
│       ├── pwa-*.png              # PWA 图标
│       └── _nuxt/                 # 预编译资源
│           ├── B7rlnwkb.js        # 入口 JS
│           ├── entry.A2e2demF.css # 入口 CSS
│           └── *.js               # 其他模块
│
├── conf/
│   ├── config.yaml                # Clash 配置
│   └── ui -> dashboard/public/    # 软链接（启动时创建）
│
└── temp/
    └── ui -> dashboard/public/    # 软链接（非 root 模式）
```

### 4.2 软链接创建

**start.sh 中的集成逻辑**：

```bash
# Dashboard 源目录
Dashboard_Src="${Work_Dir}/dashboard/public"

# 根据运行模式选择目标位置
if [ "${SYSTEMD_MODE:-false}" = "true" ] && [ "$(id -u)" -ne 0 ]; then
    # 非 root 模式：链接到 temp 目录
    Dashboard_Link="$Temp_Dir/ui"
else
    # root 模式：链接到 conf 目录
    Dashboard_Link="${Conf_Dir}/ui"
fi

# 创建软链接
ln -sfn "$Dashboard_Src" "$Dashboard_Link"

# 写入配置文件
sed -i -E "s|external-ui:.*|external-ui: ${Dashboard_Link}|g" "$CONFIG_FILE"
```

### 4.3 配置注入

**config.yaml 中的相关配置**：

```yaml
# API 监听地址
external-controller: 127.0.0.1:9090

# Dashboard 文件路径
external-ui: /opt/clash-for-linux/conf/ui

# API 认证密钥（启动时自动生成）
secret: abc123def456...
```

---

## 5. 安全设计

### 5.1 默认安全策略

| 项目 | 默认值 | 说明 |
|------|--------|------|
| external-controller | `127.0.0.1:9090` | 仅本机访问 |
| secret | 随机 64 位十六进制 | 强认证密钥 |
| TLS | 开启 | 证书校验 |

### 5.2 访问方式

**推荐方式：SSH 端口转发**

```bash
# 在本地终端执行
ssh -N -L 9090:127.0.0.1:9090 user@server

# 然后在浏览器访问
http://127.0.0.1:9090/ui
```

**公网访问（不推荐）**

如需公网访问，需修改 `.env`：

```bash
export EXTERNAL_CONTROLLER='0.0.0.0:9090'
export CLASH_SECRET='your-strong-secret-here'
```

### 5.3 Secret 管理

```bash
# 查看完整 secret
sudo sed -nE 's/^[[:space:]]*secret:[[:space:]]*//p' /opt/clash-for-linux/conf/config.yaml | head -n 1

# 脱敏显示（前4后4）
# 输出: abcd****efgh
```

---

## 6. 配置文件

### 6.1 Dashboard 配置 (config.js)

```javascript
window.__METACUBEXD_CONFIG__ = {
  defaultBackendURL: '',  // 空表示使用当前域名
}
```

### 6.2 Clash 配置 (config.yaml)

```yaml
# HTTP 混合端口（HTTP + SOCKS5）
mixed-port: 7890

# 是否允许局域网访问
allow-lan: false

# API 监听地址
external-controller: 127.0.0.1:9090

# Dashboard 路径
external-ui: /opt/clash-for-linux/conf/ui

# API 密钥
secret: ${CLASH_SECRET}

# 运行模式
mode: rule

# 日志级别
log-level: info
```

---

## 7. 启动流程

### 7.1 Dashboard 集成时序图

```
┌─────────┐    ┌──────────┐    ┌──────────┐    ┌──────────────────┐
│start.sh │    │  文件系统 │    │config.yaml│    │   Clash 内核     │
└────┬────┘    └────┬─────┘    └────┬─────┘    └────────┬─────────┘
     │              │               │                   │
     │  1. 检查 dashboard/public    │                   │
     │─────────────>│               │                   │
     │<─────────────│ exists: true  │                   │
     │              │               │                   │
     │  2. 创建软链接                │                   │
     │  ln -sfn dashboard/public conf/ui                │
     │─────────────>│               │                   │
     │              │               │                   │
     │  3. 写入 external-ui          │                   │
     │─────────────────────────────>│                   │
     │              │               │                   │
     │  4. 写入 external-controller  │                   │
     │─────────────────────────────>│                   │
     │              │               │                   │
     │  5. 写入 secret               │                   │
     │─────────────────────────────>│                   │
     │              │               │                   │
     │  6. 启动 Clash 内核           │                   │
     │───────────────────────────────────────────────────>
     │              │               │                   │
     │              │               │  7. 读取配置文件   │
     │              │               │<──────────────────│
     │              │               │                   │
     │              │               │  8. 启动 HTTP 服务│
     │              │               │  - 静态文件服务   │
     │              │               │  - API 服务       │
     │              │               │                   │
     ▼              ▼               ▼                   ▼
```

### 7.2 关键步骤说明

| 步骤 | 动作 | 说明 |
|------|------|------|
| 1 | 检查 dashboard/public | 确保 UI 文件存在 |
| 2 | 创建软链接 | `conf/ui -> dashboard/public` |
| 3 | 写入 external-ui | 告诉 Clash UI 文件位置 |
| 4 | 写入 external-controller | 配置 API 监听地址 |
| 5 | 写入 secret | 设置认证密钥 |
| 6 | 启动 Clash 内核 | 加载配置并运行 |
| 7-8 | 内核初始化 | 启动 HTTP 服务，提供 UI 和 API |

---

## 8. 调试与排查

### 8.1 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| Dashboard 无法访问 | external-controller 未启动 | 检查 Clash 进程是否运行 |
| 403 Forbidden | secret 认证失败 | 检查密钥是否正确 |
| UI 文件 404 | external-ui 路径错误 | 检查软链接是否存在 |
| SAFE_PATH 报错 | 路径不在允许范围内 | 使用 temp 目录替代 |

### 8.2 调试命令

```bash
# 检查 API 是否响应
curl http://127.0.0.1:9090/api/version

# 带认证访问
curl -H "Authorization: Bearer <secret>" http://127.0.0.1:9090/api/proxies

# 检查 UI 路径
ls -la /opt/clash-for-linux/conf/ui

# 检查配置
grep -E "external-|secret" /opt/clash-for-linux/conf/config.yaml

# 查看日志
journalctl -u clash-for-linux.service -f
```

### 8.3 SAFE_PATH 问题处理

Mihomo 内核有安全路径限制，UI 必须在允许的目录下：

```bash
# start.sh 中的处理逻辑
fix_external_ui_by_safe_paths() {
    # 从错误信息中获取允许的路径
    local base
    base="$(sed -n 's/.*allowed paths: \[\([^]]*\)\].*/\1/p' "$test_out" | head -n 1)"

    # 将 UI 文件复制到允许的路径
    local ui_dst="$base/ui"
    rsync -a --delete "$ui_src"/ "$ui_dst"/

    # 更新配置
    upsert_yaml_kv "$cfg" "external-ui" "$ui_dst"
}
```

---

## 9. 版本信息

### 9.1 当前 Dashboard 版本

- **名称**: MetaCubeXD
- **版本**: 1.235.0
- **框架**: Nuxt.js 3
- **仓库**: https://github.com/MetaCubeX/metacubexd

### 9.2 更新 Dashboard

```bash
# 下载最新版本
cd /tmp
git clone --depth 1 https://github.com/MetaCubeX/metacubexd.git
cd metacubexd

# 构建（需要 Node.js）
pnpm install
pnpm build

# 部署
rm -rf /opt/clash-for-linux/dashboard/public/*
cp -r dist/* /opt/clash-for-linux/dashboard/public/

# 重启服务
clashctl restart
```

---

## 10. 扩展开发

### 10.1 自定义 Dashboard

可以使用其他 Clash Dashboard，只需修改 `external-ui` 路径：

```yaml
# 使用 Yacd
external-ui: /path/to/yacd

# 使用 Clash Dashboard
external-ui: /path/to/clash-dashboard
```

### 10.2 自定义配置

修改 `dashboard/public/config.js`：

```javascript
window.__METACUBEXD_CONFIG__ = {
  defaultBackendURL: 'https://api.example.com',  // 自定义后端
  defaultSecret: 'your-secret',  // 默认密钥（不推荐）
}
```

### 10.3 API 代理

如需通过反向代理访问 API：

```nginx
location /clash-api/ {
    proxy_pass http://127.0.0.1:9090/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```
