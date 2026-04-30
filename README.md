# Cloudflare Auto Speed Test

自动测速 Cloudflare 优选 IP 并更新至 Cloudflare DNS 记录的自动化脚本。

## 功能特性

- 支持单域名对多 IP 测速更新 (speed_AIO.sh)
- 支持单域名对单 IP 测速更新 (speed.sh)
- 支持多地区 IP 汇总更新 (CDNDomainUpdate.sh)
- 自动按国家/地区分类 IP
- 支持自定义测速端口 (443, 2053, 2083, 2087, 2096, 8443)
- 支持 Telegram/飞书 Webhook 推送通知
- Web 测速结果展示面板 (Flask Dashboard)

## 项目结构

```
cf-auto-speed-test/
├── config.conf          # 配置文件
├── speed_AIO.sh        # 单域名对多IP测速
├── speed.sh            # 单域名对单IP测速
├── CDNDomainUpdate.sh   # 汇总更新
├── Domain2IP.py        # 域名转IP
├── RemoveCFIPs.py       # 过滤官方CF IP
├── app_dashboard.py     # Web测速面板
├── GeoLite2-Country.mmdb
└── README.md
```

## 快速开始

### 1. 安装依赖

```bash
sudo apt update
sudo apt install -y git curl unzip awk jq python3 python3-pip geoip-bin mmdb-bin
```

### 2. 配置

编辑 `config.conf`:

```bash
auth_email="your@email.com"
auth_key="your_cf_key"
zone_name="example.com"
githubID="your_github_id"

# 飞书推送 (可选，留空禁用)
feishu_webhook="https://open.feishu.cn/open-apis/bot/v2/hook/xxx"

# Telegram推送 (可选，留空禁用)
telegramBotToken=""
telegramBotUserId=""
telegramBotAPI=""
```

### 3. 运行脚本

```bash
chmod +x speed_AIO.sh speed.sh CDNDomainUpdate.sh

# 单域名对多IP (默认香港, 443端口, 4个IP)
./speed_AIO.sh

# 指定参数: 地区 端口 IP数量 域名
./speed_AIO.sh kr 443 6 example.com

# 单域名对单IP
./speed.sh hk 443 4 example.com

# 汇总更新
./CDNDomainUpdate.sh cdn example.com
```

## 脚本参数说明

### speed_AIO.sh (单域名对多IP)

| 参数 | 说明 | 默认值 |
|------|------|--------|
| $1 | 地区代码 (hk/sg/kr/jp/us) | hk |
| $2 | 端口 | 443 |
| $3 | IP数量 | 4 |
| $4 | 主域名 | config.conf |
| $5 | CloudFlare邮箱 | config.conf |
| $6 | CloudFlare API Key | config.conf |
| $7 | 自定义测速URL | 官方测速 |

### speed.sh (单域名对单IP)

| 参数 | 说明 | 默认值 |
|------|------|--------|
| $1 | 地区代码 | hk |
| $2 | 端口 | 443 |
| $3 | 域名记录数 | 4 |
| $4 | 主域名 | config.conf |
| $5 | CloudFlare邮箱 | config.conf |
| $6 | CloudFlare API Key | config.conf |
| $7 | 自定义测速URL | 官方测速 |

### CDNDomainUpdate.sh (汇总更新)

| 参数 | 说明 | 默认值 |
|------|------|--------|
| $1 | 二级域名前缀 (cdn/hk/sg...) | cdn |
| $2 | 主域名 | config.conf |
| $3 | CloudFlare邮箱 | config.conf |
| $4 | CloudFlare API Key | config.conf |

## Web 测速面板

启动 Flask Dashboard:

```bash
pip3 install flask
python3 app_dashboard.py
```

访问 `http://your-server:5001`

- 显示各地区最优 IP 列表
- 显示历史测速记录
- JSON API: `/api/results`

## 多域名批量更新

创建 `Domain.txt` 文件，每行一个域名:

```
domain1.com
domain2.com
domain3.com
```

脚本将自动解析域名对应的 IP 并加入测速池。

## 定时任务示例

```bash
# 每6小时执行一次
0 */6 * * * cd /path/to/cf-auto-speed-test && ./speed_AIO.sh hk 443 4 example.com

# 每日凌晨3点执行
0 3 * * * cd /path/to/cf-auto-speed-test && ./speed_AIO.sh kr 443 6 example.com
```

## 注意事项

- 脚本需在 Ubuntu 18.04+ 环境运行
- 运行前确保本机网络未使用代理 (仅限中国 IP)
- 建议提前在 Cloudflare 创建好对应的 DNS 记录
- 飞书/Telegram 推送可选择性配置，留空则不推送

## License

MIT License
