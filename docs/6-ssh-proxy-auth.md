# SSH 代理认证配置

本文档介绍如何通过 `ncat` 配置 SSH 的 `ProxyCommand`，实现带认证的代理连接。

## 概述

当需要通过需要认证的 HTTP 代理连接 SSH 时，可以使用 `ncat` 作为 `ProxyCommand`。`ncat` 支持通过环境变量或文件注入代理认证信息，避免将敏感信息硬编码在配置文件中。

## 方法一：直接引用环境变量

在 `~/.ssh/config` 中直接引用环境变量：

```bash
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_rsa
    IdentitiesOnly yes
    ProxyCommand ncat --proxy-type http --proxy 127.0.0.1:7890 --proxy-auth ${PROXY_USER}:${PROXY_PASS} %h %p
```

使用时设置环境变量：

```bash
export PROXY_USER="your_username"
export PROXY_PASS="your_password"
git clone git@github.com:user/repo.git
```

## 方法二：封装脚本

创建包装脚本 `~/.ssh/ncat-proxy.sh`：

```bash
#!/bin/bash
# 从环境变量读取代理认证信息
ncat --proxy-type http \
     --proxy 127.0.0.1:7890 \
     --proxy-auth "${PROXY_USER}:${PROXY_PASS}" \
     "$@"
```

添加执行权限：

```bash
chmod +x ~/.ssh/ncat-proxy.sh
```

在 `~/.ssh/config` 中调用：

```bash
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_rsa
    IdentitiesOnly yes
    ProxyCommand ~/.ssh/ncat-proxy.sh %h %p
```

## 方法三：从文件读取认证信息

创建认证文件：

```bash
echo "your_username:your_password" > ~/.ssh/proxy_auth
chmod 600 ~/.ssh/proxy_auth
```

修改脚本读取文件：

```bash
#!/bin/bash
AUTH=$(cat ~/.ssh/proxy_auth)
ncat --proxy-type http \
     --proxy 127.0.0.1:7890 \
     --proxy-auth "${AUTH}" \
     "$@"
```

## 认证参数说明

| 代理类型 | 参数格式 |
|----------|----------|
| HTTP/SOCKS5 | `--proxy-auth <username>:<password>` |
| SOCKS4 | `--proxy-auth <username>` |

`ncat` 的 HTTP 代理认证支持 Basic 和 Digest 两种方式，优先使用更安全的 Digest 认证。

## 环境变量持久化

将环境变量写入 shell 配置文件：

```bash
echo 'export PROXY_USER="your_username"' >> ~/.bashrc
echo 'export PROXY_PASS="your_password"' >> ~/.bashrc
source ~/.bashrc
```

## 方法对比

| 方法 | 优点 | 缺点 |
|------|------|------|
| 直接引用环境变量 | 简单直接 | 需要手动设置环境变量 |
| 封装脚本 | 灵活可扩展 | 需要维护额外文件 |
| 文件读取认证信息 | 更安全，权限可控 | 需要额外管理认证文件 |

## 推荐方案

- **简单场景**：方法一（直接引用环境变量）
- **安全要求高**：方法三（文件读取认证信息）
