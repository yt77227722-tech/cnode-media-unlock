# 渡云模式（Duyun Mode）全网节点部署、架构约定与资产台账全景手册

> **文档定位**：本文档为「渡云网络（duyun88.com）」最核心的运维绝密资产台账与新节点部署 SOP 指南。完整收录了 12 大落地节点真实资产、AWS 双中转转发算法、新节点 5 分钟快速通车命令及 4 级容灾方案。

---

## 一、 渡云模式核心架构全景拓扑

渡云模式采用 **「用户端 ➔ 前端中转 ➔ 后端落地 ➔ 解锁网关」四级解耦高可用架构**：

```mermaid
flowchart LR
    Client["用户客户端<br>(Clash / Sing-box / 小火箭)"]
    
    subgraph Transit["前端中转层 (Relay Tier)"]
        JP["AWS 东京 (18.183.87.200)<br>Shadowsocks 入口 (65011~65121)"]
        SG["AWS 新加坡 (13.229.59.125)<br>AnyTLS 入口 (64011~64122)"]
    end
    
    subgraph Landing["后端落地层 (Landing Tier)"]
        HK["01.1 香港落地 (140.235.141.32)"]
        TW["12.1 台湾落地 (tw2.fuckip.me / NAT)"]
        US["04.1 美国落地 (140.235.142.54)"]
        Other["新/日/韩/越/土/法/德/英/泰 落地机"]
    end
    
    subgraph Gateway["流媒体解锁网关 (Unlock Tier)"]
        Media["media-*.9527app.site:2052<br>(VMess+WS / 独立解锁网关)"]
    end

    Client -->|客户端连接中转入口| Transit
    JP -->|AWS 国际骨干高速专网| Landing
    SG -->|双路热备冗余容灾切换| Landing
    Landing -->|普通流量自由出站| Web["全球互联网 / 目标服务"]
    Landing -->|流媒体/AI 规则分流| Gateway
    Gateway -->|原生住宅 IP 访问| Streaming["Netflix / 巴哈姆特 / Disney+ / OpenAI"]
```

### 核心架构铁律：
1. **落地机 IP 零泄漏**：客户端只连接 AWS 中转 IP，落地机绝不对外暴露，免疫 GFW 探测与封锁。
2. **双中转热备（Active-Active）**：每个地区落地均同时挂载「JP 中转」与「SG 中转」，任何单台中转被墙，客户端自动无缝漂移，业务不中断。
3. **精准分流解锁**：普通下载与网页浏览由落地机自由出站，仅流媒体与 AI 流量走 2052 端口中转解锁。

---

## 二、 12 大落地节点全景资产台账

渡云全网 12 大落地节点已全部部署 `dy-anytls:55011` 与 `dy-ss:55012` 双协议监听：

| 编号 | 地区 | 节点名称 | 落地机公网 IP / 域名 | 后端 ID (共用) | 媒体解锁配置文件 | 解锁归属地区 | 备注说明 |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **01.1** | **HK** | 香港 | `140.235.141.32` | **1011** | `outbound-hk.json` | 香港 (HK) | 原生解 TVB, Viu, Bilibili 港澳台 |
| **02.1** | **SG** | 新加坡 | `141.11.46.113` | **1021** | `outbound-sg.json` | 新加坡 (SG) | 东南亚极速核心骨干 |
| **03.1** | **JP** | 日本 | `151.242.36.4` | **1031** | `outbound-jp.json` | 日本 (JP) | 原生解 Abema, DMM, Niconico |
| **04.1** | **US** | 美国 | `140.235.142.54` | **1041** | `outbound-us.json` | 美国 (US) | 原生解 Hulu, Disney+, Max, OpenAI |
| **05.1** | **KR** | 韩国 | `203.227.191.247` | **1051** | `outbound-us.json` | 美国 (US) | 韩国本土节点 |
| **06.1** | **VN** | 越南 | `103.70.114.20` | **1061** | `outbound-us.json` | 美国 (US) | 东南亚节点 |
| **07.1** | **TR** | 土耳其 | `38.180.112.204` | **1071** | `outbound-us.json` | 美国 (US) | 欧亚低价区节点 |
| **08.1** | **FR** | 法国 | `38.180.226.42` | **1081** | `outbound-us.json` | 美国 (US) | 欧洲大区节点 |
| **09.1** | **DE** | 德国 | `38.180.219.19` | **1091** | `outbound-us.json` | 美国 (US) | 欧洲大区节点 |
| **10.1** | **UK** | 英国 | `38.180.199.40` | **1101** | `outbound-us.json` | 美国 (US) | 英国本土节点 |
| **11.1** | **TH** | 泰国 | `149.33.32.231` | **1111** | `outbound-us.json` | 美国 (US) | 东南亚节点 |
| **12.1** | **TW** | 台湾 | `tw2.fuckip.me` | **1121** | `outbound-tw.json` | 台湾 (TW) | **中华电信 HiNet 动态家宽**，原生解巴哈姆特动画疯、Hami Video |

> [!NOTE]
> **台湾 NAT 端口特别标注**：
> - 台湾节点为内网 NAT 容器，AnyTLS 外部映射端口为 `1491`（对应内部 55011）；Shadowsocks 外部映射端口为 TCP `35517` / UDP `8024`（对应内部 55012）。

---

## 三、 AWS 双中转节点与精准端口转发算法

渡云前台展示的所有入口节点，全部经由 AWS 专用中转服务器进行高速转发：

### 1. 两台中转机基础参数
* **JP 中转机**：`18.183.87.200`（AWS 东京 EC2，slot_no = 1）
* **SG 中转机**：`13.229.59.125`（AWS 新加坡 EC2，slot_no = 2）

### 2. 核心端口映射算法（永不混淆公式）
* **后端主节点 ID**：`1000 + 地区编号(region_no) * 10 + 1`  
  *(例如：HK=1011, SG=1021, JP=1031, US=1041 ... TW=1121)*
* **前端展示入口 ID**：`10000 + 地区编号(region_no) * 10 + slot_no`  
  *(例如：HK 走 JP=10011，HK 走 SG=10012)*
* **中转机监听端口映射规则**：
  * **JP 中转机 (Shadowsocks 入口)**：`65000 + region_no * 10 + 1` ➔ 转发到落地机的 `55012`
  * **SG 中转机 (AnyTLS 入口)**：`64000 + region_no * 10 + 2` ➔ 转发到落地机的 `55011`

### 3. 渡云端口标准对照表
| 协议类型 | 渡云落地监听端口 | 渡云中转入口端口范围 | 协议特性 |
| :--- | :---: | :---: | :--- |
| **AnyTLS** | **`55011`** | **`64011 ~ 64122`** | 强烈推荐！长连接池化复用，抗 GFW 阻断能力极强 |
| **Shadowsocks** | **`55012`** | **`65011 ~ 65121`** | 极速轻量，支持 SS2022，全平台客户端通用 |
| **解锁网关** | **`2052`** | — | VMess+WS 解锁通道（UUID: `bf417eb3-d283-5487-b6ad-9a9be278be8a`） |

---

## 四、 极速开辟全新节点 SOP（两行命令 5 分钟通车）

当你购买了一台新的落地 VPS（如香港、台湾、日本、欧洲等），按以下 3 步即可极速通车：

### 步骤 1：在落地机上执行一键部署（30秒）
登录新买的落地机，执行以下命令：
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yt77227722-tech/cnode-media-unlock/main/scripts/deploy_duyun_node.sh) \
  -name "TW-HiNet-02" \
  -node_id 1122 \
  -region tw \
  -type both
```
* **参数速查**：
  * `-name`：节点代号（如 `TW-02`、`HK-03`）
  * `-node_id`：渡云面板后端的父节点 ID（如 `1122`）
  * `-region`：流媒体解锁区域（`tw`、`hk`、`us` 或 `general`）
  * `-type`：`both`（同时部署 AnyTLS 和 Shadowsocks）
* 执行后会自动安装 cnode、对接面板、开启 55011/55012 监听，并输出落地机公网 IP。

---

### 步骤 2：在中转机上配置端口转发（10秒）
登录你的 AWS 中转机（或任意一台备用中转机），执行以下命令：
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yt77227722-tech/cnode-media-unlock/main/scripts/deploy_duyun_relay.sh) \
  -listen 65122 \
  -remote <你的落地机IP>:55011
```
* 自动开启 Linux BBR 加速并配置 Realm 极速端口映射（支持 TCP+UDP）。

---

### 步骤 3：在渡云面板后台（duyun88.com/admin）添加前台节点（1分钟）
1. 登录面板后台 ➔ 点击【节点管理】 ➔ 【新增节点】；
2. **连接地址 (Host)**：填入**中转机的公网 IP**（如 `18.183.87.200` 或中转域名）；
3. **服务端口 (Port)**：填入**中转端口**（如 `65122`）；
4. **内部服务端口**：填入**落地端口**（如 `55011`）；
5. **父节点 ID (Parent ID)**：选择步骤 1 中填写的后端节点 ID（如 `1122`）；
6. 保存后，客户端刷新订阅，全新线路立刻全网通车！🎉

---

## 五、 解锁中转网关（media-*.9527app.site:2052）灾备自建与恢复

如果上游解锁网关（`media-*.9527app.site:2052`）故障或掉线，如何快速恢复？

### 步骤 1：在任意一台具有原生解锁能力的 VPS 上一键自建新网关
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yt77227722-tech/cnode-media-unlock/main/scripts/deploy_media_gateway.sh)
```
* 自动在 `0.0.0.0:2052` 启动 VMess+WS 网关，将请求以本机原生 IP 直连外网。

### 步骤 2：秒级全网恢复
* **方案 A（改 DNS，推荐）**：在 Cloudflare 将 `media-hk-*.9527app.site`（或你自定的域名）A 记录指向新网关 IP。**全网所有落地节点 0 改动，秒级无缝恢复！**
* **方案 B（改配置）**：将你的域名写入 GitHub 仓库的 `config/outbound-*.json`，落地机执行 `systemctl restart cnode` 即可。

---

## 六、 4 级阶梯式容灾切换手则（保证业务 100% 不掉线）

| 故障场景 | 容灾级别 | 操作方法 | 生效耗时 | 对用户的影响 |
| :--- | :---: | :--- | :---: | :---: |
| **单台 AWS 中转被墙/宕机** | **第 1 级** | 无需操作！客户端默认配置了 JP/SG 双中转，客户端自动漂移至备选中转 | 0 秒 | 完全无感 |
| **AWS 中转 IP 被 GFW 阻断** | **第 2 级** | 登录 AWS EC2 控制台 ➔ Elastic IPs ➔ 分配并绑定新弹性 IP ➔ 释放旧 IP ➔ 更新面板 Host 或修改中转域名解析 | 30 秒 | 刷新订阅即恢复 |
| **AWS 整体故障/不想用 AWS** | **第 3 级** | 拿任意一台小鸡运行 `deploy_duyun_relay.sh` 转发到落地机，面板 Host 改为该小鸡 IP | 1 分钟 | 刷新订阅即恢复 |
| **所有中转全挂（紧急救援）** | **第 4 级** | 登录渡云后台，将节点的连接地址（Host）直接改成**落地机真实 IP**，降级为直连模式 | 10 秒 | 瞬间全网通车 |

---

## 七、 渡云源站架构、数据库与日常运维命令

### 1. 渡云源站配置底账
* **源站 IP**：`38.59.230.13`（SSH: root:22，公钥认证）
* **管理后台**：`https://duyun88.com/04ff1ba4`（管理员邮箱: `tinger231@gmail.com`）
* **运行架构**：Docker Compose (`/opt/lnmpr/docker-compose.yaml`) 托管 Nginx + PHP 8.3 + MariaDB + Redis
* **在线源码**：`/opt/lnmpr/www/v2_dy`（xv2board v1.7.5）
* **数据库名**：`v2_dy`（容器内执行：`docker exec -it mariadb sh -lc 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" v2_dy'`）
* **自动备份**：每天凌晨 03:00 自动打包并推送最新备份到 Telegram

### 2. 日常排查命令速查
```bash
# 落地机查看 cnode 状态与心跳日志
systemctl status cnode
journalctl -u cnode -f -n 50
systemctl restart cnode

# 中转机查看 Realm 端口转发状态
systemctl status duyun-relay
journalctl -u duyun-relay -f -n 50

# 查看当前中转连接并发数
netstat -nat | grep ESTABLISHED | wc -l
```

---

## 八、 永久 GitHub 资源调用直链

* **GitHub 仓库主页**：[`https://github.com/yt77227722-tech/cnode-media-unlock`](https://github.com/yt77227722-tech/cnode-media-unlock)
* **落地机一键部署脚本**：
  `https://raw.githubusercontent.com/yt77227722-tech/cnode-media-unlock/main/scripts/deploy_duyun_node.sh`
* **中转机一键转发脚本**：
  `https://raw.githubusercontent.com/yt77227722-tech/cnode-media-unlock/main/scripts/deploy_duyun_relay.sh`
* **独立解锁网关一键脚本**：
  `https://raw.githubusercontent.com/yt77227722-tech/cnode-media-unlock/main/scripts/deploy_media_gateway.sh`
* **全套解锁配置目录**：
  `https://github.com/yt77227722-tech/cnode-media-unlock/tree/main/config`
