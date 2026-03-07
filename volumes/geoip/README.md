# GeoIP 数据库目录

存放 Clash/Mihomo 使用的 GeoIP 数据库文件。

## 文件说明

- `Country.mmdb` - MaxMind GeoIP 数据库，用于 GEOIP 规则匹配

## 更新数据库

可以从以下地址下载最新版本：

```bash
# 下载 GeoIP 数据库
curl -L -o volumes/geoip/Country.mmdb https://gitlab.com/Masaiki/GeoIP2-CN/-/raw/release/Country.mmdb

# 或使用 Clash Meta 的 GeoIP
curl -L -o volumes/geoip/Country.mmdb https://github.com/Dreamacro/maxmind-geoip/releases/latest/download/Country.mmdb
```

## 自动链接

启动脚本会自动创建软链接：
- `conf/Country.mmdb` -> `volumes/geoip/Country.mmdb`
