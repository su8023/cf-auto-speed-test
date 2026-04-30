# Cloudflare 优选 IP 测速工具

> 自动测速 Cloudflare 各类端口，筛选出最优 IP 并更新到 Cloudflare DNS，一键部署，小白也能用。

---

## 功能特性

| 功能 | 说明 |
|------|------|
| 多地区测速 | 支持 HK/JP/KR/SG/TW/TH/VN/ID/MY/PH/IN 等亚洲地区，以及 US/UK/DE/NL/FR 等欧美地区 |
| 多端口支持 | 443 / 2053 / 2083 / 2087 / 2096 / 8443 |
| 自动筛选 | 按延迟/速度排序，自动保留最优 IP |
| DNS 自动更新 | 测速完成后自动更新 Cloudflare DNS 记录 |
| 飞书/TG 通知 | 测速结果推送至飞书群或 Telegram |
| Web 面板 | 浏览器查看测速结果历史记录 |
| 定时任务 | 支持 Linux crontab 自动每日/每小时执行 |
| 一键部署 | 一条命令完成安装+配置，自动化引导 |

---

## 目录

- [一、准备工作](#一准备工作) —— 注册 Cloudflare、获取 API Key
- [二、一键安装](#二一键安装) —— 一条命令搞定一切
- [三、交互配置说明](#三交互配置说明) —— 每一步在做什么
- [四、手动测速](#四手动测速) —— 单独跑测速命令
- [五、Web 面板](#五web-面板) —— 浏览器看结果
- [六、定时任务](#六定时任务) —— 每天自动跑
- [七、常见问题](#七常见问题)
- [八、卸载](#八卸载)

---

## 一、准备工作

### 1.1 注册 Cloudflare 账号

1. 访问 [https://dash.cloudflare.com](https://dash.cloudflare.com)
2. 点击 **Sign Up** 注册账号（用邮箱即可）
3. 登录后把需要优选 IP 的**主域名**添加到 Cloudflare

> **注意**：域名必须已经接入 Cloudflare（即 DNS 由 Cloudflare 管理），测速结果才能自动写入。

### 1.2 获取 Cloudflare API Key

1. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com)
2. 点击右上角头像 → **My Profile**
3. 左侧菜单找到 **API Keys**
4. 找到 **Global API Key**，点击 **View** 查看

```
格式类似：c2547eb745afd46cda2c5b4xxxxxxxxxxxx
```

> ⚠️ 不要使用 **Origin CA Token**，那个是给 CDN 源站证书用的，这里的脚本需要的是 Global API Key。

### 1.3 确认域名已接入 Cloudflare

在 Cloudflare Dashboard 的 **DNS** 设置里，确认：
- 域名状态是 **Active**（橙色云朵）
- 有至少一条 **A 记录**（可以是 `@` 指向任意 IP，例如 `1.1.1.1`，后续脚本会自动更新）

---

## 二、一键安装

### 2.1 一条命令完成全部

在 Linux 终端（VPS、开发机均可）执行：

```bash
wget -qO- https://raw.githubusercontent.com/su8023/cf-auto-speed-test/main/install.sh | bash
```

> 支持 Ubuntu 18.04+ / Debian / CentOS，系统会自动检测。

脚本会自动：
- ✅ 检测并安装缺失的依赖（wget/curl/jq/python3 等）
- ✅ 下载最新版本脚本到 `/opt/cf-auto-speed-test`
- ✅ 进入交互式配置向导，一步步引导填写参数

---

## 三、交互配置说明

安装过程中会逐步提示，逐一说明：

### 第一步：填写 CloudFlare 邮箱

```
CloudFlare 邮箱 [xxx@example.com]:
```

输入你在 Cloudflare 注册的邮箱地址。

---

### 第二步：填写 CloudFlare API Key

```
CloudFlare API Key [输入回车保留上次的]:
```

输入上一步拿到的 Global API Key。**输入时屏幕不显示**，这是正常的，输入完回车即可。

---

### 第三步：填写主域名

```
主域名 (例: example.com) [yourdomain.com]:
```

输入已接入 Cloudflare 的主域名，例如 `example.com`（不要加 https://，也不要加 www）。

---

### 第四步：选择测速地区

```
可选测速地址列表（Cloudflare 数据中心）
─────────────────────────────────────
[亚洲]
 1) HK  香港      7) TW  台湾     13) PH  菲律宾
 2) JP  日本      8) TH  泰国     14) VN  越南
 3) KR  韩国      9) MY  马来西亚 15) ID  印尼
 4) SG  新加坡   10) IN  印度
                  11) JP2 日本大阪

[欧美]
16) US  美国     18) DE  德国     20) FR  法国
17) UK  英国     19) NL  荷兰     21) IT  意大利
22) ES  西班牙  23) PL  波兰     24) SE  瑞典

[其他]
25) AU  澳洲     27) BR  巴西
26) CA  加拿大   28) ZA  南非

 0) 全部地区

请输入测速地区编号（支持多选如 1 2 3，默认: 1）:
```

输入编号，可选多个，用空格分隔，例如：

- `1` —— 只测香港
- `1 2 3` —— 测香港+日本+韩国
- `0` —— 全部地区都测（耗时较长）

---

### 第五步：填写测速端口

```
测速端口 (默认: 443):
```

常用端口说明：

| 端口 | 说明 | 兼容性 |
|------|------|--------|
| 443 | 标准 HTTPS | 最通用 |
| 2053 | CF Game HTTP/3 | 适合游戏 |
| 2083 | CF Game HTTPS | 适合游戏 |
| 2087 | CF Enterprise | 企业版 |
| 2096 | CF HTTP/3 | 通用 |
| 8443 | CF 备用 | 通用 |

新手建议直接回车默认 443。

---

### 第六步：填写每地区优选 IP 数量

```
每个地区优选 IP 数量 (默认: 4):
```

测速完成后，每个地区保留几个最优 IP。默认 4 个足够用。

---

### 第七步：飞书 Webhook（可选）

```
飞书 Webhook URL (留空跳过):
```

如果有飞书群机器人，在这里填入 Webhook 地址。留空直接回车跳过。

---

### 第八步：GitHub IP 库 ID

```
GitHub IP 库 ID [ansoncloud8]:
```

IP 素材来源，填 `ansoncloud8` 或其他 CF IP 收集者的 GitHub 用户名。直接回车默认即可。

---

### 配置验证

填写完毕后会自动验证 CloudFlare 凭证是否正确：

```
[OK] CloudFlare 验证通过 (Zone ID: a1b2c3d4...)
```

验证失败会提示检查填写内容。

---

## 四、手动测速

安装完成后，单独跑测速命令：

```bash
cd /opt/cf-auto-speed-test
```

### 4.1 使用已保存的配置测速

```bash
# 一键测速（使用安装时保存的地区和参数）
./install.sh --test
```

### 4.2 指定参数测速

```bash
# 格式：./speed_AIO.sh 地区 端口 IP数量 域名

# 示例：香港 + 443端口 + 保留4个最优IP
./speed_AIO.sh hk 443 4 example.com

# 示例：日本 + 2053端口 + 保留6个最优IP
./speed_AIO.sh jp 2053 6 example.com

# 示例：韩国 + 443端口 + 保留8个最优IP
./speed_AIO.sh kr 443 8 example.com
```

### 4.3 地区代码对照表

| 代码 | 地区 |  | 代码 | 地区 |
|------|------|------|------|------|
| hk | 香港 | | th | 泰国 |
| jp | 日本 | | my | 马来西亚 |
| jp2 | 日本大阪 | | ph | 菲律宾 |
| kr | 韩国 | | vn | 越南 |
| sg | 新加坡 | | id | 印尼 |
| tw | 台湾 | | in | 印度 |
| us | 美国 | | uk | 英国 |
| de | 德国 | | nl | 荷兰 |
| fr | 法国 | | it | 意大利 |

### 4.4 测速结果在哪看

测速完成后会自动打印结果，类似：

```
=== 测速结果 ===
香港最优 IP：
  162.159.xx.xx  延迟:23ms  速度:85Mbps
  172.64.xx.xx   延迟:25ms  速度:78Mbps
  ...

日本最优 IP：
  104.18.xx.xx   延迟:41ms  速度:72Mbps
  ...
```

同时 DNS 记录会自动更新到 Cloudflare。

---

## 五、Web 面板

测速结果可视化网页界面。

### 5.1 启动面板

```bash
./install.sh --dashboard
```

输出：

```
[OK] Web 面板已启动 → http://你的服务器IP:5001
```

### 5.2 访问面板

在浏览器打开显示的地址，可以：
- 查看各地区最优 IP 列表
- 查看历史测速记录
- 查看测速趋势

### 5.2 API 接口

```
GET http://服务器IP:5001/api/results
```

返回 JSON 格式测速结果，可供其他程序调用。

---

## 六、定时任务

每天自动跑一次测速，不需要人工干预。

### 6.1 设置定时任务

```bash
./install.sh --cron
```

默认每天早上 **6:00** 自动测速（只跑配置时的第一个地区）。

### 6.2 查看当前定时任务

```bash
crontab -l | grep cf-auto-speed-test
```

### 6.3 修改定时时间

```bash
crontab -e
```

找到对应那行，修改时间。格式说明：

```
分 时 日 月 周 命令
```

| 示例 | 含义 |
|------|------|
| `0 6 * * *` | 每天 6:00 |
| `0 */6 * * *` | 每 6 小时 |
| `0 6,18 * * *` | 每天 6:00 和 18:00 |

---

## 七、常见问题

### Q1：提示 `bash: wget: command not found`

系统没有 wget，执行：

```bash
apt update && apt install -y wget curl jq python3
```

### Q2：提示 `CloudFlare 验证失败`

- 检查邮箱是否正确
- 检查 API Key 是否是 **Global API Key**（不是 Origin CA Token）
- 检查域名是否已接入 Cloudflare（状态为 Active）

### Q3：测速很慢或超时

- 每次测速有 90 秒超时，属于正常（IP 数量多时需要等待）
- 某些地区如果长时间没响应，可以只选网络好的地区测速

### Q4：测速结果全部为空

- 检查本机网络是否能访问 Cloudflare（没有被墙）
- 确认 Cloudflare DNS 记录存在（A 记录，代理状态任意）

### Q5：想更换测速地区

```bash
./install.sh --config
```

重新进入配置向导，可以重新选择地区。

### Q6：如何查看日志

```bash
# Web 面板日志
cat /var/log/cf-dashboard.log

# 最近 50 条实时日志
tail -50 /var/log/cf-dashboard.log
```

### Q7：提示 `Permission denied`

需要用 root 权限运行：

```bash
sudo bash install.sh
```

### Q8：多域名怎么操作

在 `/opt/cf-auto-speed-test` 目录创建 `Domain.txt`，每行一个主域名：

```
domain1.com
domain2.com
domain3.com
```

然后运行 `./CDNDomainUpdate.sh cdn domain1.com` 汇总更新。

---

## 八、卸载

```bash
./install.sh --uninstall
```

会清除：
- `/opt/cf-auto-speed-test` 目录
- 定时任务
- Web 面板进程

---

## 命令一览

```bash
# 一键安装+配置
wget -qO- https://raw.githubusercontent.com/su8023/cf-auto-speed-test/main/install.sh | bash

# 重新配置
wget -qO- https://raw.githubusercontent.com/su8023/cf-auto-speed-test/main/install.sh | bash -s -- --config

# 测速
wget -qO- https://raw.githubusercontent.com/su8023/cf-auto-speed-test/main/install.sh | bash -s -- --test

# 启动面板
wget -qO- https://raw.githubusercontent.com/su8023/cf-auto-speed-test/main/install.sh | bash -s -- --dashboard

# 定时任务
wget -qO- https://raw.githubusercontent.com/su8023/cf-auto-speed-test/main/install.sh | bash -s -- --cron

# 卸载
wget -qO- https://raw.githubusercontent.com/su8023/cf-auto-speed-test/main/install.sh | bash -s -- --uninstall
```

---

## License

MIT License
