# 分流配置指南

本文档介绍如何配置多订阅分流策略，实现特定流量走指定代理。

## 使用场景

- 访问公司内网（如 GitLab）走公司代理
- 其他流量走个人订阅
- 无需手动切换，自动路由

## 快速开始

### 1. 配置环境变量

编辑 `.env` 文件，添加 work 代理配置：

```bash
# Work 代理配置
export WORK_PROXY_HOST='代理服务器地址'
export WORK_PROXY_PORT='代理端口'
export WORK_PROXY_USER='用户名'
export WORK_PROXY_PASS='密码'
```

### 2. 创建分流配置文件

创建 `conf/routing-config.yaml`：

```yaml
# 分流配置示例

port: 7890
socks-port: 7891
mixed-port: 7892
allow-lan: false
mode: rule
log-level: info
external-controller: 127.0.0.1:9090

dns:
  enable: true
  enhanced-mode: fake-ip
  nameserver:
    - 223.5.5.5
    - 119.29.29.29

proxies:
  - name: work-proxy
    type: socks5
    server: ${WORK_PROXY_HOST}
    port: ${WORK_PROXY_PORT}
    username: ${WORK_PROXY_USER}
    password: ${WORK_PROXY_PASS}

proxy-providers:
  personal:
    type: http
    url: https://your-subscription-url&flag=clash
    interval: 3600
    path: ./proxy-providers/personal.yaml
    health-check:
      enable: true
      interval: 600
      url: http://www.gstatic.com/generate_204

proxy-groups:
  - name: work
    type: select
    proxies:
      - work-proxy

  - name: personal
    type: select
    use:
      - personal

rules:
  # 公司内网 IP 段
  - IP-CIDR,10.200.0.0/16,work
  # 公司域名
  - DOMAIN-SUFFIX,company.com,work
  # 其他流量
  - MATCH,personal
```

### 3. 添加为本地订阅

```bash
just add routing local:/path/to/routing-config.yaml
```

### 4. 切换到分流配置

```bash
just use routing
```

切换时会自动：
- 替换环境变量（如 `${WORK_PROXY_HOST}`）
- 重启服务使配置生效

## 规则类型

### IP-CIDR

匹配 IP 地址或 IP 段：

```yaml
rules:
  # 单个 IP
  - IP-CIDR,192.168.1.100/32,work
  # IP 段
  - IP-CIDR,10.0.0.0/8,work
  - IP-CIDR,172.16.0.0/12,work
  - IP-CIDR,192.168.0.0/16,work
```

### DOMAIN-SUFFIX

匹配域名后缀：

```yaml
rules:
  - DOMAIN-SUFFIX,google.com,personal
  - DOMAIN-SUFFIX,github.com,personal
  - DOMAIN-SUFFIX,company.internal,work
```

### DOMAIN

精确匹配域名：

```yaml
rules:
  - DOMAIN,gitlab.company.com,work
```

### SRC-IP-CIDR

匹配来源 IP（客户端 IP）：

```yaml
rules:
  - SRC-IP-CIDR,192.168.1.0/24,direct
```

### PROCESS-NAME

匹配进程名：

```yaml
rules:
  - PROCESS-NAME,ssh,direct
  - PROCESS-NAME,curl,personal
```

### GEOIP

匹配地理位置：

```yaml
rules:
  - GEOIP,CN,direct
  - GEOIP,US,personal
```

### 最终规则

`MATCH` 必须放在最后，匹配所有未匹配的流量：

```yaml
rules:
  - MATCH,personal
```

## 代理组类型

### select

手动选择：

```yaml
proxy-groups:
  - name: my-group
    type: select
    proxies:
      - node-1
      - node-2
```

### url-test

自动选择延迟最低的节点：

```yaml
proxy-groups:
  - name: auto
    type: url-test
    proxies:
      - node-1
      - node-2
    url: http://www.gstatic.com/generate_204
    interval: 300
```

### fallback

按顺序尝试，第一个可用则使用：

```yaml
proxy-groups:
  - name: backup
    type: fallback
    proxies:
      - node-1
      - node-2
    url: http://www.gstatic.com/generate_204
    interval: 300
```

### load-balance

负载均衡：

```yaml
proxy-groups:
  - name: balance
    type: load-balance
    strategy: consistent-hashing
    proxies:
      - node-1
      - node-2
    url: http://www.gstatic.com/generate_204
    interval: 300
```

## 环境变量

在配置文件中使用 `${VAR_NAME}` 语法引用环境变量：

```yaml
proxies:
  - name: work-proxy
    type: socks5
    server: ${WORK_PROXY_HOST}
    port: ${WORK_PROXY_PORT}
    username: ${WORK_PROXY_USER}
    password: ${WORK_PROXY_PASS}
```

切换订阅时会自动替换。

## 常见配置示例

### 公司内网分流

```yaml
rules:
  # 公司内网 IP
  - IP-CIDR,10.0.0.0/8,work
  - IP-CIDR,172.16.0.0/12,work
  - IP-CIDR,192.168.0.0/16,work
  # 公司域名
  - DOMAIN-SUFFIX,internal.company.com,work
  - DOMAIN-SUFFIX,gitlab.company.com,work
  # 其他
  - MATCH,personal
```

### 国内直连

```yaml
rules:
  # 国内直连
  - GEOIP,CN,direct
  # 其他走代理
  - MATCH,personal
```

### 广告拦截

```yaml
rules:
  # 广告域名
  - DOMAIN-SUFFIX,ad.com,REJECT
  - DOMAIN-KEYWORD,analytics,REJECT
  # 其他
  - MATCH,personal
```

## 调试

查看当前生效的规则：

```bash
# 查看配置文件中的规则
grep -A 20 "^rules:" conf/config.yaml

# 通过 API 查看规则
curl -s http://127.0.0.1:9090/rules -H "Authorization: Bearer $(grep secret conf/config.yaml | awk '{print $2}')"
```

测试特定域名的路由：

```bash
# 测试域名匹配
curl -s "http://127.0.0.1:9090/providers/proxies/personal" \
  -H "Authorization: Bearer <secret>"
```

## 注意事项

1. **规则顺序**：从上到下匹配，第一个匹配的规则生效
2. **MATCH 规则**：必须放在最后
3. **敏感信息**：使用环境变量，不要硬编码密码
4. **配置文件**：不要提交到 git（已在 `.gitignore` 中排除）

## 相关命令

```bash
# 列出订阅
just list

# 切换订阅
just use <name>

# 查看状态
just status

# 重启服务
just restart
```
