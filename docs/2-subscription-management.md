# 多订阅管理设计文档

本文档详细描述 clash-for-linux 的多订阅管理机制设计与实现。

---

## 1. 功能概述

多订阅管理允许用户维护多个 Clash 订阅地址，并在不同订阅之间快速切换，适用于以下场景：

- 工作与个人订阅分离
- 主订阅与备用订阅切换
- 多机场订阅管理

### 核心能力

| 能力 | 说明 |
|------|------|
| 添加订阅 | 将订阅信息持久化存储 |
| 删除订阅 | 从列表中移除订阅 |
| 列出订阅 | 查看所有订阅及当前激活状态 |
| 切换订阅 | 激活指定订阅，更新运行配置 |
| 更新订阅 | 下载最新配置并应用 |

---

## 2. 数据模型

### 2.1 订阅列表文件

**路径**: `conf/subscriptions.list`

**格式**: 管道符分隔的纯文本

```
name|url|headers|updated
```

| 字段 | 说明 | 示例 |
|------|------|------|
| name | 订阅名称（唯一标识） | `office` |
| url | 订阅地址 | `https://example.com/subscribe` |
| headers | 请求头（可选） | `User-Agent: Clash` |
| updated | 最后更新时间（ISO 8601） | `2025-01-15T10:00:00Z` |

**示例文件内容**:

```
office|https://sub1.example.com/office|User-Agent: ClashforWindows/0.20.39|2025-01-15T10:00:00Z
personal|https://sub2.example.com/personal|-|-
backup|https://sub3.example.com/backup|Authorization: Bearer token123|2025-01-10T08:30:00Z
```

### 2.2 环境变量

**路径**: `.env`

多订阅管理涉及三个环境变量：

| 变量 | 说明 | 示例 |
|------|------|------|
| `CLASH_URL` | 当前激活的订阅地址 | `https://sub1.example.com/office` |
| `CLASH_HEADERS` | 当前订阅的请求头 | `User-Agent: Clash` |
| `CLASH_SUBSCRIPTION` | 当前激活的订阅名称 | `office` |

### 2.3 数据关系图

```
┌─────────────────────────────────────────────────────────────────┐
│                  conf/subscriptions.list                        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ office|https://...|User-Agent: Clash|2025-01-15T...     │   │
│  │ personal|https://...|-|-                                │   │
│  │ backup|https://...|Authorization: Bearer xxx|2025-01-10 │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
         │
         │  sub use office 时写入
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                        .env                                     │
│                                                                 │
│  export CLASH_URL='https://sub1.example.com/office'             │
│  export CLASH_HEADERS='User-Agent: Clash'                       │
│  export CLASH_SUBSCRIPTION='office'                             │
└─────────────────────────────────────────────────────────────────┘
         │
         │  update.sh 读取
         ▼
┌─────────────────────────────────────────────────────────────────┐
│                   conf/config.yaml                              │
│                                                                 │
│  # 由 update.sh 下载并生成                                      │
│  mixed-port: 7890                                               │
│  proxies:                                                       │
│    - name: "node1"                                              │
│      ...                                                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. 命令接口

### 3.1 命令一览

```bash
clashctl sub add <name> <url> [headers]   # 添加订阅
clashctl sub del <name>                   # 删除订阅
clashctl sub use <name>                   # 切换订阅
clashctl sub update [name]                # 更新订阅
clashctl sub list                         # 列出所有订阅
clashctl sub log                          # 查看更新日志
```

### 3.2 命令详解

#### `sub add` - 添加订阅

```bash
clashctl sub add office "https://sub.example.com/office" "User-Agent: Clash"
```

**行为**:

1. 检查 `subscriptions.list` 是否存在，不存在则创建
2. 检查订阅名称是否已存在
3. 追加写入 `name|url|headers|-`

#### `sub del` - 删除订阅

```bash
clashctl sub del office
```

**行为**:

1. 查找订阅是否存在
2. 从 `subscriptions.list` 中移除对应行
3. 若删除的是当前激活订阅，不会自动切换

#### `sub use` - 切换订阅

```bash
clashctl sub use office
```

**行为**:

1. 从 `subscriptions.list` 查找订阅信息
2. 更新 `.env` 中的 `CLASH_URL`、`CLASH_HEADERS`、`CLASH_SUBSCRIPTION`
3. **不会自动更新配置**，需手动执行 `clashctl restart` 或 `clashctl sub update`

#### `sub update` - 更新订阅

```bash
clashctl sub update office
# 或更新当前激活订阅
clashctl sub update
```

**行为**:

1. 获取订阅名称（参数或从 `.env` 读取）
2. 调用 `sub use` 切换到该订阅
3. 执行 `update.sh` 下载最新配置
4. 更新 `subscriptions.list` 中的时间戳

#### `sub list` - 列出订阅

```bash
clashctl sub list
```

**输出示例**:

```
NAME                 ACTIVE URL
office               yes    https://sub1.example.com/office
personal             no     https://sub2.example.com/personal
backup               no     https://sub3.example.com/backup
```

#### `sub log` - 查看更新日志

```bash
clashctl sub log
```

**输出示例**:

```
NAME                 LAST_UPDATE
office               2025-01-15T10:00:00Z
personal             -
backup               2025-01-10T08:30:00Z
```

---

## 4. 核心函数

### 4.1 函数列表

| 函数 | 文件 | 用途 |
|------|------|------|
| `subscription_lookup` | clashctl | 查找订阅记录 |
| `subscription_add` | clashctl | 添加订阅 |
| `subscription_del` | clashctl | 删除订阅 |
| `subscription_use` | clashctl | 激活订阅 |
| `subscription_touch` | clashctl | 更新时间戳 |
| `subscription_update` | clashctl | 更新订阅配置 |
| `subscription_list` | clashctl | 列出订阅 |
| `subscription_log` | clashctl | 显示更新日志 |
| `set_env_var` | clashctl | 写入环境变量 |
| `ensure_subscription_file` | clashctl | 确保订阅文件存在 |

### 4.2 函数实现

#### `subscription_lookup(name)`

查找指定名称的订阅记录。

```bash
subscription_lookup() {
    local name="$1"
    awk -F'|' -v target="$name" '$1 == target {print; exit}' "$SUBSCRIPTION_FILE"
}
```

**返回**: 完整的订阅行 `name|url|headers|updated` 或空

#### `subscription_add(name, url, headers)`

添加新订阅到列表。

```bash
subscription_add() {
    local name="$1"
    local url="$2"
    local headers="${3:-}"

    # 参数校验
    if [ -z "$name" ] || [ -z "$url" ]; then
        echo "[ERROR] 用法: clashctl sub add <name> <url> [headers]" >&2
        exit 1
    fi

    # 确保文件存在
    ensure_subscription_file

    # 检查是否重复
    if subscription_lookup "$name" >/dev/null; then
        echo "[ERROR] 订阅已存在: $name" >&2
        exit 1
    fi

    # 追加写入
    printf "%s|%s|%s|-\n" "$name" "$url" "$headers" >> "$SUBSCRIPTION_FILE"
    echo "[OK] 已添加订阅: $name"
}
```

#### `subscription_use(name)`

激活指定订阅，更新 `.env` 文件。

```bash
subscription_use() {
    local name="$1"

    # 查找订阅
    local line
    line=$(subscription_lookup "$name")
    if [ -z "$line" ]; then
        echo "[ERROR] 未找到订阅: $name" >&2
        exit 1
    fi

    # 解析字段
    local url headers
    url=$(echo "$line" | awk -F'|' '{print $2}')
    headers=$(echo "$line" | awk -F'|' '{print $3}')

    # 写入 .env
    set_env_var "CLASH_URL" "$url"
    set_env_var "CLASH_HEADERS" "$headers"
    set_env_var "CLASH_SUBSCRIPTION" "$name"

    echo "[OK] 已切换订阅: $name"
}
```

#### `subscription_touch(name)`

更新订阅的最后更新时间。

```bash
subscription_touch() {
    local name="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # 使用 awk 更新指定行的第4列
    awk -F'|' -v target="$name" -v ts="$timestamp" \
        'BEGIN{OFS=FS} {if ($1==target) {$4=ts} print}' \
        "$SUBSCRIPTION_FILE" > "${SUBSCRIPTION_FILE}.tmp"
    mv "${SUBSCRIPTION_FILE}.tmp" "$SUBSCRIPTION_FILE"
}
```

#### `set_env_var(key, value)`

安全地更新 `.env` 文件中的环境变量。

```bash
set_env_var() {
    local key="$1"
    local value="${2:-}"

    # 转义特殊字符
    local escaped escaped_sed
    escaped=$(printf "%s" "$value" | sed "s/'/'\"'\"'/g")
    escaped_sed=$(printf "%s" "$escaped" | sed 's/[\\&@]/\\&/g')

    # 存在则替换，不存在则追加
    if grep -q "^export ${key}=" "$ENV_FILE"; then
        sed -i "s@^export ${key}=.*@export ${key}='${escaped_sed}'@" "$ENV_FILE"
    else
        echo "export ${key}='${escaped}'" >> "$ENV_FILE"
    fi
}
```

---

## 5. 流程图

### 5.1 添加订阅流程

```
┌─────────────────┐
│ sub add <args>  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│ 参数校验        │────>│ 参数缺失，退出  │
│ name, url 非空? │     │                 │
└────────┬────────┘     └─────────────────┘
         │ 通过
         ▼
┌─────────────────┐     ┌─────────────────┐
│ 查找订阅        │────>│ 订阅已存在，退出│
│ subscription    │     │                 │
│ _lookup(name)   │     └─────────────────┘
└────────┬────────┘
         │ 不存在
         ▼
┌─────────────────┐
│ 追加写入        │
│ subscriptions   │
│ .list           │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ [OK] 已添加订阅 │
└─────────────────┘
```

### 5.2 切换订阅流程

```
┌─────────────────┐
│ sub use <name>  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌─────────────────┐
│ 查找订阅        │────>│ 未找到，退出    │
│ subscription    │     │                 │
│ _lookup(name)   │     └─────────────────┘
└────────┬────────┘
         │ 找到
         ▼
┌─────────────────┐
│ 解析 url,       │
│ headers         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 更新 .env       │
│ - CLASH_URL     │
│ - CLASH_HEADERS │
│ - CLASH_        │
│   SUBSCRIPTION  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ [OK] 已切换订阅 │
│                 │
│ 提示: 需 restart│
│ 或 update 生效  │
└─────────────────┘
```

### 5.3 更新订阅流程

```
┌─────────────────────────┐
│ sub update [name]       │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐     ┌─────────────────────┐
│ 获取订阅名称            │     │ 未指定且 .env 中    │
│ - 参数传入?             │     │ 无 CLASH_SUBSCRIPTION│
│ - 从 .env 读取?         │────>│ 退出报错            │
└────────────┬────────────┘     └─────────────────────┘
             │
             ▼
┌─────────────────────────┐
│ subscription_use(name)  │
│ 切换到该订阅            │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ run_script("update.sh") │
│ - 下载订阅配置          │
│ - 生成 config.yaml      │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ subscription_touch(name)│
│ 更新时间戳              │
└────────────┬────────────┘
             │
             ▼
┌─────────────────────────┐
│ [OK] 订阅已更新         │
│ 提示: 需 restart 生效   │
└─────────────────────────┘
```

### 5.4 完整时序图

```
┌─────────┐    ┌──────────┐    ┌──────────────────┐    ┌──────────┐    ┌──────────┐
│  用户   │    │ clashctl │    │subscriptions.list│    │   .env   │    │update.sh │
└────┬────┘    └────┬─────┘    └────────┬─────────┘    └────┬─────┘    └────┬─────┘
     │              │                   │                   │               │
     │  sub add office "url"            │                   │               │
     │─────────────>│                   │                   │               │
     │              │ subscription_lookup("office")         │               │
     │              │──────────────────>│                   │               │
     │              │<──────────────────│ (not found)       │               │
     │              │                   │                   │               │
     │              │ printf "office|url|headers|-"         │               │
     │              │──────────────────>│                   │               │
     │<─────────────│ [OK] 已添加订阅   │                   │               │
     │              │                   │                   │               │
     │              │                   │                   │               │
     │  sub use office                  │                   │               │
     │─────────────>│                   │                   │               │
     │              │ subscription_lookup("office")         │               │
     │              │──────────────────>│                   │               │
     │              │<──────────────────│ "office|url|hdrs|-"               │
     │              │                   │                   │               │
     │              │ set_env_var("CLASH_URL", url)         │               │
     │              │───────────────────────────────────────>               │
     │              │ set_env_var("CLASH_HEADERS", headers) │               │
     │              │───────────────────────────────────────>               │
     │              │ set_env_var("CLASH_SUBSCRIPTION", "office")           │
     │              │───────────────────────────────────────>               │
     │<─────────────│ [OK] 已切换订阅   │                   │               │
     │              │                   │                   │               │
     │              │                   │                   │               │
     │  sub update office               │                   │               │
     │─────────────>│                   │                   │               │
     │              │ subscription_use("office")            │               │
     │              │──────────────────>│                   │               │
     │              │<──────────────────│                   │               │
     │              │                   │                   │               │
     │              │ run_script("update.sh")               │               │
     │              │───────────────────────────────────────────────────────>│
     │              │                   │                   │               │
     │              │                   │                   │  下载新配置   │
     │              │                   │                   │  生成config   │
     │              │<───────────────────────────────────────────────────────│
     │              │                   │                   │               │
     │              │ subscription_touch("office")          │               │
     │              │──────────────────>│                   │               │
     │              │                   │ 更新时间戳        │               │
     │<─────────────│ [OK] 订阅已更新   │                   │               │
     │              │                   │                   │               │
     ▼              ▼                   ▼                   ▼               ▼
```

---

## 6. 状态管理

### 6.1 订阅状态

```
┌─────────────┐      sub add       ┌─────────────┐
│   不存在    │ ─────────────────> │   已存储    │
└─────────────┘                    └──────┬──────┘
                                          │
                              sub use     │
                           ┌──────────────┘
                           │
                           ▼
┌───────────────────────────────────────────────────────────┐
│                         已激活                            │
│                                                           │
│  .env 文件状态:                                           │
│    export CLASH_URL='https://...'                         │
│    export CLASH_HEADERS='User-Agent: ...'                 │
│    export CLASH_SUBSCRIPTION='<订阅名称>'                  │
│                                                           │
│  当前运行配置: .env 中的 CLASH_URL 对应的订阅              │
└───────────────────────────────────────────────────────────┘
                           │
                           │ sub update
                           │
                           ▼
┌───────────────────────────────────────────────────────────┐
│                         已更新                            │
│                                                           │
│  - conf/config.yaml 已更新为最新配置                      │
│  - subscriptions.list 中的时间戳已更新                    │
│  - 需要 restart 才能应用新配置                            │
└───────────────────────────────────────────────────────────┘
```

### 6.2 当前激活订阅判断

```bash
# 读取当前激活订阅名称
active=$(awk -F= '/^export CLASH_SUBSCRIPTION=/{print $2}' "$ENV_FILE" | tr -d "'" | tr -d '"')

# 判断是否激活
if [ "$name" = "$active" ]; then
    echo "当前激活"
fi
```

---

## 7. 使用示例

### 7.1 典型工作流

```bash
# 1. 添加多个订阅
clashctl sub add office "https://sub1.example.com/office" "User-Agent: Clash"
clashctl sub add personal "https://sub2.example.com/personal"
clashctl sub add backup "https://sub3.example.com/backup"

# 2. 查看订阅列表
clashctl sub list
# NAME                 ACTIVE URL
# office               no     https://sub1.example.com/office
# personal             no     https://sub2.example.com/personal
# backup               no     https://sub3.example.com/backup

# 3. 切换到工作订阅并更新
clashctl sub use office
clashctl sub update
clashctl restart

# 4. 切换到个人订阅
clashctl sub use personal
clashctl sub update
clashctl restart

# 5. 查看更新日志
clashctl sub log
# NAME                 LAST_UPDATE
# office               2025-01-15T10:00:00Z
# personal             2025-01-15T10:05:00Z
# backup               -
```

### 7.2 与 systemd 配合

```bash
# 切换订阅后重启服务
clashctl sub use office
sudo systemctl restart clash-for-linux.service

# 或使用 clashctl
clashctl sub use office
clashctl sub update
clashctl restart
```

---

## 8. 设计决策

### 8.1 为什么使用纯文本文件？

| 方案 | 优点 | 缺点 |
|------|------|------|
| **纯文本 (选用)** | 无依赖、易读、易备份、版本控制友好 | 查询效率低（但订阅数量少可忽略） |
| SQLite | 查询高效 | 需要额外依赖、增加复杂度 |
| JSON | 结构化、工具支持好 | Bash 解析不便 |

### 8.2 为什么切换后不自动更新配置？

1. **安全考虑**: 避免意外切换导致服务中断
2. **可控性**: 用户可能只想切换但不立即应用
3. **一致性**: 与 `set-url` 命令行为一致

### 8.3 为什么删除当前订阅不会自动切换？

1. **避免意外**: 用户可能误删
2. **明确意图**: 用户应明确选择下一个订阅

---

## 9. 错误处理

### 9.1 常见错误

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| `未找到订阅: xxx` | 订阅名称不存在 | 使用 `sub list` 查看已有订阅 |
| `订阅已存在: xxx` | 添加重复名称 | 使用不同名称或先删除 |
| `未指定订阅名称，且 CLASH_SUBSCRIPTION 未设置` | 更新时无激活订阅 | 指定订阅名称或先切换 |
| `未找到 .env 文件` | 环境变量文件丢失 | 检查安装目录 |

### 9.2 错误恢复

```bash
# 如果 .env 丢失，可以手动重新切换订阅
clashctl sub use <name>

# 如果 subscriptions.list 丢失，需要重新添加
clashctl sub add <name> <url>
```

---

## 10. 扩展点

### 10.1 添加订阅分组

可扩展数据格式支持分组：

```
group|name|url|headers|updated
work|office|https://...|...|...
work|backup|https://...|...|...
personal|main|https://...|...|...
```

### 10.2 添加订阅有效性检查

```bash
# 可扩展 subscription_add 添加 URL 有效性检查
subscription_add() {
    # ...
    # 检查 URL 是否可访问
    if ! curl -sSf -o /dev/null "$url"; then
        echo "[WARN] 订阅地址可能不可用"
    fi
    # ...
}
```

### 10.3 添加订阅自动更新

可扩展 systemd timer 实现定时更新：

```ini
# /etc/systemd/system/clash-update.timer
[Unit]
Description=Update Clash subscription daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```
