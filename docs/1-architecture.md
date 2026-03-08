# 架构设计文档

本文档描述 clash-for-linux 的整体架构、模块职责与开发规范。

---

## 1. 项目定位

clash-for-linux 是一个面向 Linux 服务器/桌面环境的 **Clash 自动化运行与管理脚本集**。

### 核心目标

- 开箱即用：无需手动配置复杂的 systemd 服务
- 可维护：配置、日志、二进制分离
- 可回滚：支持多订阅管理与配置兜底
- 安全默认：管理接口仅绑定本机，自动生成 Secret

### 技术选型

| 层级 | 技术 | 说明 |
|------|------|------|
| 代理内核 | Clash Meta / Mihomo | 支持 VLESS、Hysteria 等新协议 |
| 脚本语言 | Bash | 严格模式 `set -euo pipefail` |
| 服务管理 | systemd | 支持自动重启、日志管理 |
| 订阅转换 | subconverter (可选) | 将 v2rayN 等订阅转为 Clash 格式 |

---

## 2. 目录结构

```
clash-for-linux/
├── libs/                         # 二进制/库文件
│   ├── clash/                    # Clash 内核
│   │   ├── clash-linux-amd64     # x86_64 架构
│   │   ├── clash-linux-arm64     # ARM64 架构
│   │   └── clash-linux-armv7     # ARMv7 架构
│   │
│   └── subconverter/             # 订阅转换工具
│       ├── linux-amd64/          # x86_64 架构
│       ├── linux-arm64/          # ARM64 架构
│       └── linux-armv7/          # ARMv7 架构
│
├── scripts/                      # 所有脚本
│   ├── lib/                      # 库脚本（被 source）
│   │   ├── cpu-arch.sh           # CPU 架构检测
│   │   ├── clash-resolve.sh      # Clash 二进制解析
│   │   ├── port-check.sh         # 端口检测
│   │   ├── config-check.sh       # 配置工具函数
│   │   ├── systemd-utils.sh      # systemd 工具
│   │   ├── env-utils.sh          # 环境变量工具
│   │   └── output.sh             # 输出格式化
│   │
│   └── cmd/                      # 执行脚本
│       ├── service-install.sh    # 安装服务
│       ├── service-uninstall.sh  # 卸载服务
│       ├── service-start.sh      # 启动服务
│       ├── service-stop.sh       # 停止服务
│       ├── service-restart.sh    # 重启服务
│       ├── subscription-update.sh # 订阅更新
│       └── systemd-setup.sh      # systemd 配置
│
├── conf/                         # 配置文件目录
│   ├── config.yaml               # 主配置文件（运行态）
│   ├── fallback_config.yaml      # 兜底配置
│   ├── subscriptions.list        # 多订阅列表
│   ├── mixin.d -> ../volumes/mixin.d  # Mixin 软链接
│   └── Country.mmdb -> ../volumes/geoip/Country.mmdb  # GeoIP 软链接
│
├── volumes/                      # 用户数据目录
│   ├── geoip/                    # GeoIP 数据库
│   │   └── Country.mmdb
│   └── mixin.d/                  # Mixin 配置目录
│       └── *.yaml                # 按文件名排序合并
│
├── logs/                         # 日志目录
├── temp/                         # 临时文件目录
│
├── docs/                         # 文档目录
│
├── .env                          # 环境变量配置
├── Makefile                      # 命令入口
├── clashctl                      # 统一命令行管理工具
├── CLAUDE.md                     # Claude Code 指引
└── README.md                     # 项目说明
```

---

## 3. 模块架构

### 3.1 整体架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                      clashctl (CLI 入口)                         │
│   start / stop / restart / status / update / sub 管理           │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                     start.sh (启动编排)                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │get_cpu_arch │  │resolve_clash│  │ port_utils  │             │
│  │    .sh      │  │    .sh      │  │    .sh      │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │config_utils │  │clash_profile│  │resolve_sub  │             │
│  │    .sh      │  │_conversion  │  │converter.sh │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└───────────────────────────┬─────────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────────┐
│                  Clash 内核 (Mihomo / Meta)                      │
│  ┌────────────────────────────────────────────────────────┐     │
│  │  HTTP Proxy (7890) │ SOCKS5 (7891) │ Redir (7892)      │     │
│  │  External API (9090)                                      │     │
│  └────────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 模块职责

| 模块 | 文件 | 职责 |
|------|------|------|
| CLI 入口 | `clashctl` | 统一命令行接口，支持 systemd 与直接执行两种模式 |
| 命令入口 | `Makefile` | make start/stop/restart/update/status/env |
| 启动编排 | `scripts/cmd/service-start.sh` | 订阅下载、配置生成、内核启动 |
| 停止服务 | `scripts/cmd/service-stop.sh` | 进程终止、PID 清理 |
| 安装服务 | `scripts/cmd/service-install.sh` | 一键安装、systemd 配置 |
| CPU 架构 | `scripts/lib/cpu-arch.sh` | 检测系统 CPU 架构（amd64/arm64/armv7） |
| 二进制解析 | `scripts/lib/clash-resolve.sh` | 根据架构选择对应 Clash 内核 |
| 端口管理 | `scripts/lib/port-check.sh` | 端口冲突检测与自动分配 |
| 配置工具 | `scripts/lib/config-check.sh` | Tun 配置、Mixin 合并 |
| systemd 工具 | `scripts/lib/systemd-utils.sh` | 服务单元生成、profile.d 安装 |
| 输出格式化 | `scripts/lib/output.sh` | 彩色输出、日志格式 |

---

## 4. 启动流程

### 4.1 流程图

```
┌─────────────────────┐
│  1. 加载 .env       │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│  2. 检测 CPU 架构    │
│     选择二进制       │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│  3. 端口冲突检测    │
│     自动分配可用端口 │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│  4. 订阅地址检测    │
│     下载配置文件     │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│  5. 配置解析        │
│  ┌────────────────┐ │
│  │ 完整 Clash YAML│ │──→ 直接使用
│  └────────────────┘ │
│  ┌────────────────┐ │
│  │ 非标准格式     │ │──→ subconverter 转换
│  └────────────────┘ │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│  6. 注入配置        │
│  - external-controller
│  - secret           │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│  7. Mixin 合并      │
│     按文件名排序    │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│  8. 启动 Clash 内核 │
│     写入 PID 文件   │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│  9. 生成环境变量    │
│     proxy_on/down   │
└─────────────────────┘
```

### 4.2 关键逻辑说明

#### systemd 模式 vs 手动模式

| 场景 | 行为 |
|------|------|
| systemd 模式 (`SYSTEMD_MODE=true`) | 订阅失败时使用兜底配置，不退出 |
| 手动模式 | 订阅失败直接退出，提示用户 |

#### 配置优先级

```
订阅配置 < Mixin 配置 < 运行时注入
```

---

## 5. 安装流程

### 5.1 install.sh 时序图

```
┌─────────┐     ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  用户   │     │install.sh│    │.env/脚本 │    │install_  │    │ systemd  │
│         │     │          │    │  模块    │    │systemd.sh│    │          │
└────┬────┘     └────┬─────┘    └────┬─────┘    └────┬─────┘    └────┬─────┘
     │               │               │               │               │
     │  sudo bash install.sh         │               │               │
     │──────────────>│               │               │               │
     │               │               │               │               │
     │               │═══════════════════════════════════════════════│
     │               │  1. 前置校验  │               │               │
     │               │  - 检查 root 权限             │               │
     │               │  - 检查 .env 文件存在         │               │
     │               │═══════════════════════════════════════════════│
     │               │               │               │               │
     │               │──────────────>│               │               │
     │               │  2. 同步文件到安装目录        │               │
     │               │  (rsync/cp 到 /opt/clash-for-linux)          │
     │               │               │               │               │
     │               │──────────────>│               │               │
     │               │  3. 设置脚本执行权限          │               │
     │               │  chmod +x *.sh scripts/* bin/* clashctl      │
     │               │               │               │               │
     │               │──────────────>│               │               │
     │               │  4. 加载环境与依赖脚本        │               │
     │               │  source .env  │               │               │
     │               │  source scripts/*.sh          │               │
     │               │<──────────────│               │               │
     │               │  返回 CpuArch │               │               │
     │               │               │               │               │
     │               │═══════════════════════════════════════════════│
     │               │  5. 交互式填写订阅地址        │               │
     │               │  (若 CLASH_URL 为空)         │               │
     │               │═══════════════════════════════════════════════│
     │<──────────────│               │               │               │
     │  提示输入订阅地址             │               │               │
     │──────────────>│               │               │               │
     │               │  写入 .env    │               │               │
     │               │               │               │               │
     │               │──────────────>│               │               │
     │               │  6. 端口冲突检测              │               │
     │               │  is_port_in_use()            │               │
     │               │               │               │               │
     │               │──────────────>│               │               │
     │               │  7. 创建目录结构              │               │
     │               │  conf/ logs/ temp/           │               │
     │               │               │               │               │
     │               │──────────────>│               │               │
     │               │  8. Clash 内核就绪检查        │               │
     │               │  resolve_clash_bin()          │               │
     │               │               │               │               │
     │               │──────────────>│               │               │
     │               │  9. 调用 install_systemd.sh   │               │
     │               │───────────────────────────────>               │
     │               │               │               │               │
     │               │               │               │ 生成 service │
     │               │               │               │ 单元文件     │
     │               │               │               │──────────────>│
     │               │               │               │               │
     │               │               │               │ daemon-reload │
     │               │               │               │──────────────>│
     │               │<───────────────────────────────               │
     │               │               │               │               │
     │               │──────────────>│               │               │
     │               │ 10. systemctl enable          │               │
     │               │     systemctl start           │               │
     │               │───────────────────────────────────────────────>│
     │               │               │               │               │
     │               │──────────────>│               │               │
     │               │ 11. 安装 profile.d 脚本       │               │
     │               │  /etc/profile.d/clash-for-linux.sh            │
     │               │               │               │               │
     │               │──────────────>│               │               │
     │               │ 12. 安装 clashctl 到 /usr/local/bin           │
     │               │               │               │               │
     │               │──────────────>│               │               │
     │               │ 13. 等待 config.yaml 生成     │               │
     │               │     读取 secret 并脱敏显示    │               │
     │               │               │               │               │
     │<──────────────│               │               │               │
     │  输出安装结果 │               │               │               │
     │  - 安装目录   │               │               │               │
     │  - 服务状态   │               │               │               │
     │  - API 地址   │               │               │               │
     │  - Secret     │               │               │               │
     │  - 下一步操作 │               │               │               │
     │               │               │               │               │
     ▼               ▼               ▼               ▼               ▼
```

### 5.2 安装步骤详解

| 步骤 | 动作 | 说明 |
|------|------|------|
| **1** | 前置校验 | 检查 root 权限、.env 文件存在 |
| **2** | 同步文件 | 将项目同步到 `/opt/clash-for-linux` |
| **3** | 设置权限 | `chmod +x` 所有脚本和二进制 |
| **4** | 加载依赖 | source 环境变量和工具脚本 |
| **5** | 交互填写 | CLASH_URL 为空时提示输入订阅地址 |
| **6** | 端口检测 | 检测 7890/7891/7892/9090 端口冲突 |
| **7** | 创建目录 | 创建 `conf/` `logs/` `temp/` |
| **8** | 内核检查 | 验证 Clash 二进制就绪 |
| **9** | systemd 安装 | 生成 service 单元文件 |
| **10** | 服务启动 | enable + start systemd 服务 |
| **11** | profile.d | 安装 `proxy_on/down` 快捷命令 |
| **12** | clashctl | 安装到 `/usr/local/bin` |
| **13** | 结果输出 | 显示 API 地址、Secret、下一步操作 |

### 5.3 关键决策点

```
                    ┌─────────────────────┐
                    │  CLASH_URL 为空?    │
                    └──────────┬──────────┘
                               │
              ┌────────────────┴────────────────┐
              │                                 │
              ▼                                 ▼
    ┌─────────────────┐               ┌─────────────────┐
    │ 交互式提示输入  │               │  跳过，使用已有 │
    │ (TTY 环境)      │               │  CLASH_URL      │
    └─────────────────┘               └─────────────────┘

                    ┌─────────────────────┐
                    │  systemd 可用?      │
                    └──────────┬──────────┘
                               │
              ┌────────────────┴────────────────┐
              │                                 │
              ▼                                 ▼
    ┌─────────────────┐               ┌─────────────────┐
    │ 安装 systemd    │               │ 跳过服务单元    │
    │ 服务并启动      │               │ 提示用 clashctl │
    └─────────────────┘               └─────────────────┘
```

### 5.4 install_systemd.sh 行为

`install_systemd.sh` 负责生成 systemd 服务单元文件：

```ini
[Unit]
Description=Clash for Linux
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/clash-for-linux
ExecStart=/bin/bash /opt/clash-for-linux/start.sh
ExecStop=/bin/bash /opt/clash-for-linux/shutdown.sh
Restart=on-failure
RestartSec=5
TimeoutStartSec=120
TimeoutStopSec=30
Environment=SYSTEMD_MODE=true
Environment=CLASH_ENV_FILE=/opt/clash-for-linux/temp/clash-for-linux.sh

[Install]
WantedBy=multi-user.target
```

---

## 6. 配置层次

### 6.1 配置文件关系

```
.env (环境变量)
    │
    ├── CLASH_URL ──────────→ 订阅下载地址
    ├── CLASH_SECRET ───────→ API 密钥
    ├── CLASH_HTTP_PORT ────→ HTTP 代理端口
    └── ...

conf/config.yaml (主配置)
    │
    ├── 来自订阅下载
    └── 注入运行时配置

conf/mixin.d/*.yaml (Mixin 配置)
    │
    ├── 10-base.yaml
    ├── 20-rules.yaml
    └── ... (按文件名排序合并)

conf/fallback_config.yaml (兜底配置)
    │
    └── 订阅失败时使用
```

### 6.2 环境变量说明

| 变量 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `CLASH_URL` | 是 | - | 订阅地址 |
| `CLASH_SECRET` | 否 | 自动生成 | API 密钥 |
| `CLASH_HTTP_PORT` | 否 | 7890 | HTTP 代理端口 |
| `CLASH_SOCKS_PORT` | 否 | 7891 | SOCKS5 代理端口 |
| `CLASH_REDIR_PORT` | 否 | 7892 | 透明代理端口 |
| `EXTERNAL_CONTROLLER` | 否 | 127.0.0.1:9090 | API 监听地址 |
| `CLASH_LISTEN_IP` | 否 | 127.0.0.1 | 代理监听 IP |
| `CLASH_ALLOW_LAN` | 否 | false | 允许局域网访问 |

---

## 7. 服务管理

### 7.1 systemd 配置

```ini
[Unit]
Description=Clash for Linux
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/clash-for-linux
ExecStart=/bin/bash /opt/clash-for-linux/scripts/cmd/service-start.sh
ExecStop=/bin/bash /opt/clash-for-linux/scripts/cmd/service-stop.sh
Restart=on-failure
RestartSec=5
TimeoutStartSec=120
TimeoutStopSec=30
Environment=SYSTEMD_MODE=true
Environment=SAFE_PATHS=/opt/clash-for-linux:/root/.config/mihomo

[Install]
WantedBy=multi-user.target
```

### 7.2 服务特性

- **低权限运行**：默认以 `clash` 用户运行，非 root
- **自动重启**：异常退出后 5 秒自动重启
- **日志管理**：通过 `journalctl -u clash-for-linux.service` 查看

---

## 8. 多订阅管理

### 8.1 数据结构

```
# conf/subscriptions.list
# 格式: name|url|headers|updated
office|https://example.com/office|User-Agent: Clash|-
personal|https://example.com/personal|-|2025-01-15T10:00:00Z
```

### 8.2 clashctl 命令

```bash
# 添加订阅
clashctl sub add <name> <url> [headers]

# 列出订阅
clashctl sub list

# 切换订阅
clashctl sub use <name>

# 更新订阅
clashctl sub update [name]

# 删除订阅
clashctl sub del <name>
```

---

## 9. 安全设计

### 9.1 默认安全策略

| 项目 | 默认值 | 说明 |
|------|--------|------|
| external-controller | 127.0.0.1:9090 | 仅本机访问 |
| Secret | 随机生成 | 64 位十六进制 |
| TLS 校验 | 开启 | 不跳过证书验证 |
| 运行用户 | clash | 低权限用户 |

### 9.2 安全建议

- 不建议将 `EXTERNAL_CONTROLLER` 设置为 `0.0.0.0:9090`
- 如需公网访问，确保 `CLASH_SECRET` 足够复杂

---

## 10. 开发规范

### 10.1 脚本规范

```bash
#!/bin/bash
# 严格模式
set -euo pipefail

# 错误处理
trap 'rc=$?; echo "[ERR] rc=$rc line=$LINENO cmd=$BASH_COMMAND" >&2' ERR
```

### 10.2 函数命名规范

| 前缀 | 用途 | 示例 |
|------|------|------|
| `ensure_` | 确保资源存在 | `ensure_subconverter` |
| `resolve_` | 解析并返回值 | `resolve_clash_bin` |
| `force_` | 强制写入/更新 | `force_write_secret` |
| `is_` | 布尔判断 | `is_running` |
| `action_` | 执行动作 | `action_with_systemd` |

### 10.3 日志规范

```bash
# 信息
echo "[INFO] message"

# 警告
echo -e "\033[33m[WARN]\033[0m message"

# 错误
echo -e "\033[31m[ERROR]\033[0m message" >&2

# 成功
echo -e "\033[32m[OK]\033[0m message"
```

### 10.4 文件命名规范

| 类型 | 命名 | 示例 |
|------|------|------|
| 脚本文件 | 小写下划线 | `start.sh`, `port_utils.sh` |
| 配置文件 | 小写 | `config.yaml`, `fallback_config.yaml` |
| Mixin 文件 | 数字前缀 + 描述 | `10-base.yaml`, `20-rules.yaml` |

---

## 11. 扩展点

### 11.1 添加新架构支持

1. 在 `bin/` 目录添加二进制文件：`clash-linux-<arch>`
2. 修改 `scripts/get_cpu_arch.sh` 添加架构识别逻辑
3. 修改 `scripts/resolve_clash.sh` 添加二进制选择逻辑

### 11.2 添加新的 Mixin 配置

```bash
# 创建 Mixin 文件
cat > conf/mixin.d/30-custom.yaml << 'EOF'
rules:
  - DOMAIN-SUFFIX,example.com,PROXY
EOF

# 重启服务生效
clashctl restart
```

### 11.3 自定义订阅转换

设置环境变量指定 subconverter：

```bash
export SUBCONVERTER_PATH=/path/to/custom/subconverter
export SUBCONVERTER_AUTO_DOWNLOAD=false
```

---

## 12. 版本兼容性

### 12.1 支持的操作系统

- Ubuntu 18.04+
- Debian 10+
- CentOS 7+
- RHEL 7+
- 其他使用 systemd 的 Linux 发行版

### 12.2 支持的架构

| 架构 | 二进制文件 |
|------|-----------|
| x86_64 / amd64 | `clash-linux-amd64` |
| aarch64 / arm64 | `clash-linux-arm64` |
| armv7l | `clash-linux-armv7` |

---

## 13. 参考链接

- [Clash Meta (Mihomo) 文档](https://wiki.metacubex.one/)
- [subconverter 项目](https://github.com/tindy2013/subconverter)
