# 故障排查指南

本文档收集 clash-for-linux 常见问题及解决方案。

---

## 1. 服务启动问题

### 1.1 服务启动后立即退出

**症状**：
```bash
systemctl status clash-for-linux
# 显示: inactive (dead) 或 failed
```

**排查步骤**：

```bash
# 查看详细日志
journalctl -u clash-for-linux.service -n 100 --no-pager

# 检查配置文件是否存在
ls -la /opt/clash-for-linux/conf/config.yaml

# 检查 Clash 内核是否可执行
ls -la /opt/clash-for-linux/libs/clash/clash-linux-*
```

**常见原因**：

| 原因 | 解决方案 |
|------|----------|
| `CLASH_URL` 未配置 | 编辑 `.env` 设置订阅地址 |
| 订阅地址不可访问 | 检查网络或使用代理下载 |
| 配置文件语法错误 | 使用 `clash -t -f config.yaml` 测试 |
| 二进制权限问题 | `chmod +x libs/clash/clash-linux-*` |

### 1.2 订阅下载失败

**症状**：
```
[ERROR] Clash订阅地址不可访问！
```

**排查步骤**：

```bash
# 手动测试订阅地址
curl -I "https://your-subscription-url"

# 检查是否需要代理
unset http_proxy https_proxy
curl -I "https://your-subscription-url"

# 检查请求头
curl -H "User-Agent: Clash" "https://your-subscription-url"
```

**解决方案**：

1. 如果服务器在国内，可能需要设置代理才能访问订阅地址
2. 部分机场需要特定 User-Agent，在 `.env` 中设置：
   ```bash
   export CLASH_HEADERS='User-Agent: ClashforWindows/0.20.39'
   ```

### 1.3 端口被占用

**症状**：
```
[WARN] 检测到端口冲突: 7890
```

**排查步骤**：

```bash
# 查看端口占用
ss -tlnp | grep 7890
netstat -tlnp | grep 7890

# 查看占用进程
lsof -i :7890
```

**解决方案**：

1. 停止占用端口的服务
2. 或在 `.env` 中修改端口：
   ```bash
   export CLASH_HTTP_PORT=17890
   export CLASH_SOCKS_PORT=17891
   ```
3. 设置为 `auto` 自动分配可用端口：
   ```bash
   export CLASH_HTTP_PORT=auto
   ```

---

## 2. API 问题

### 2.1 External Controller 无法访问

**症状**：
- API 请求无响应
- 显示 404 或 502 错误

**排查步骤**：

```bash
# 检查 API 是否响应
curl http://127.0.0.1:9090/api/version

# 检查服务状态
systemctl status clash-for-linux

# 检查端口监听
ss -tlnp | grep 9090
```

**常见原因**：

| 原因 | 解决方案 |
|------|----------|
| 服务未运行 | `make start` 启动服务 |
| external-controller 配置错误 | 检查 `conf/config.yaml` |

### 2.2 认证失败 (403 Forbidden)

**症状**：
- API 请求返回 403

**排查步骤**：

```bash
# 查看 secret
grep secret /opt/clash-for-linux/conf/config.yaml

# 测试 API 认证
curl -H "Authorization: Bearer YOUR_SECRET" http://127.0.0.1:9090/api/proxies
```

**解决方案**：

1. 确保使用正确的 secret
2. 如果 secret 包含特殊字符，尝试 URL 编码
3. 重新生成 secret：
   ```bash
   openssl rand -hex 32
   # 然后更新 config.yaml 中的 secret
   ```

---

## 3. 代理问题

### 3.1 代理不生效

**症状**：
- 设置了 `proxy_on` 但 curl 仍直连
- 环境变量未生效

**排查步骤**：

```bash
# 检查环境变量
env | grep -i proxy

# 检查 Clash 是否监听
ss -tlnp | grep 7890

# 测试代理连接
curl -x http://127.0.0.1:7890 https://google.com -I
```

**解决方案**：

1. 确保已 source 环境变量：
   ```bash
   source /etc/profile.d/clash-for-linux.sh
   proxy_on
   ```

2. 检查 Clash 配置中的端口设置

### 3.2 部分节点超时

**症状**：
- 某些节点无法连接
- 延迟测试失败

**排查步骤**：

```bash
# 查看 Clash 日志
tail -f /opt/clash-for-linux/logs/clash.log

# 测试节点连通性
curl -x socks5://127.0.0.1:7891 https://api.ipify.org
```

**常见原因**：

| 原因 | 解决方案 |
|------|----------|
| 节点已失效 | 更新订阅 `make update` |
| 协议不支持 | 确认使用 Mihomo 内核 |
| 端口被封锁 | 尝试其他节点或端口 |

---

## 4. GeoIP/GeoSite 问题

### 4.1 GeoSite.dat 损坏

**症状**：
```
level=warning msg="GeoSite.dat invalid, remove and download"
level=error msg="proto: cannot parse invalid wire-format data"
```

**解决方案**：

```bash
# 删除损坏文件
rm -f /opt/clash-for-linux/conf/GeoSite.dat

# 手动下载
wget -O /opt/clash-for-linux/conf/GeoSite.dat \
  "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"

# 重启服务
make restart
```

### 4.2 Country.mmdb 缺失

**症状**：
```
level=info msg="Can't find MMDB, start download"
```

**解决方案**：

```bash
# 下载 MMDB
wget -O /opt/clash-for-linux/volumes/geoip/Country.mmdb \
  "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/country.mmdb"
```

---

## 5. 脚本错误

### 5.1 `local: can only be used in a function`

**原因**：Bash 脚本中 `local` 关键字在函数外使用

**解决方案**：已在新版本中修复，请更新脚本

### 5.2 权限不足

**症状**：
```
[ERR] root-only mode: please run as root
```

**解决方案**：

```bash
# 使用 sudo 或切换到 root
sudo make start
# 或
sudo -i
make start
```

---

## 6. 性能问题

### 6.1 内存占用过高

**排查步骤**：

```bash
# 查看 Clash 进程内存
ps aux | grep clash

# 查看连接数
curl -H "Authorization: Bearer YOUR_SECRET" http://127.0.0.1:9090/api/connections | jq length
```

**解决方案**：

1. 使用 `memconservative` GeoIP 模式（默认）
2. 减少规则数量
3. 定期清理连接

### 6.2 CPU 占用过高

**常见原因**：

- 大量连接活动
- 规则匹配开销
- DNS 查询频繁

**解决方案**：

1. 使用 fake-ip 模式减少 DNS 查询
2. 优化规则配置
3. 检查是否有异常流量

---

## 7. 调试技巧

### 7.1 启用调试模式

```bash
# 前台运行 Clash，查看详细输出
SAFE_PATHS=/opt/clash-for-linux \
  /opt/clash-for-linux/libs/clash/clash-linux-amd64 \
  -f /opt/clash-for-linux/conf/config.yaml \
  -d /opt/clash-for-linux/conf
```

### 7.2 测试配置文件

```bash
# 验证配置语法
SAFE_PATHS=/opt/clash-for-linux \
  ./libs/clash/clash-linux-amd64 \
  -t -f conf/config.yaml
```

### 7.3 查看实时日志

```bash
# systemd 日志
journalctl -u clash-for-linux.service -f

# Clash 日志文件
tail -f /opt/clash-for-linux/logs/clash.log
```

### 7.4 网络诊断

```bash
# 测试代理连通性
curl -x http://127.0.0.1:7890 https://api.ipify.org
curl -x socks5://127.0.0.1:7891 https://api.ipify.org

# 测试 API
curl http://127.0.0.1:9090/api/version

# 查看路由
ip route
```

---

## 8. 恢复操作

### 8.1 重置配置

```bash
# 备份当前配置
cp /opt/clash-for-linux/conf/config.yaml /opt/clash-for-linux/conf/config.yaml.bak

# 重新下载订阅
make update

# 重启服务
make restart
```

### 8.2 完全重装

```bash
# 卸载
sudo make uninstall

# 清理配置（可选）
rm -rf /opt/clash-for-linux/conf/*
rm -rf /opt/clash-for-linux/logs/*
rm -rf /opt/clash-for-linux/temp/*

# 重新安装
sudo make install
```

---

## 9. 获取帮助

1. 查看项目文档：`docs/` 目录
2. 提交 Issue：https://github.com/wnlen/clash-for-linux/issues
3. 提供以下信息以便排查：
   - 操作系统版本
   - CPU 架构
   - 错误日志 (`journalctl -u clash-for-linux.service -n 100`)
   - 配置文件（脱敏后）
