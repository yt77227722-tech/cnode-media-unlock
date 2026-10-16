#!/bin/bash
# ==============================================================================
# 渡云模式 - 中转机（Relay）一键端口转发与网络加速脚本
# 适用：AWS EC2 / 阿里云 / 腾讯云 / 任何中转 VPS
# 底层引擎：Realm 高性能端口转发（Rust 编写，资源占用仅几MB，支持 TCP+UDP）
# ==============================================================================

set -e

LISTEN_PORT=""
REMOTE_HOST=""
REMOTE_PORT=""

usage() {
    echo "用法: bash deploy_duyun_relay.sh -listen <中转端口> -remote <落地IP:落地端口>"
    echo "示例: bash deploy_duyun_relay.sh -listen 65011 -remote 140.235.141.32:55011"
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        -listen)
            LISTEN_PORT="$2"
            shift 2
            ;;
        -remote)
            REMOTE="$2"
            REMOTE_HOST="${REMOTE%%:*}"
            REMOTE_PORT="${REMOTE##*:}"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

if [ -z "$LISTEN_PORT" ] || [ -z "$REMOTE_HOST" ] || [ -z "$REMOTE_PORT" ]; then
    echo "❌ 缺少必填参数！"
    usage
fi

echo "=========================================================="
echo " 正在部署 渡云模式 中转端口转发"
echo " 中转本地监听: 0.0.0.0:$LISTEN_PORT"
echo " 转发目标落地: $REMOTE_HOST:$REMOTE_PORT (TCP+UDP)"
echo "=========================================================="

# 1. 安装基础依赖与 Realm
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq curl tar ca-certificates
elif command -v yum >/dev/null 2>&1; then
    yum install -y curl tar ca-certificates
fi

REALM_BIN="/usr/local/bin/realm"
if [ ! -f "$REALM_BIN" ]; then
    echo "正在下载 Realm 高性能转发内核..."
    TMP_DIR=$(mktemp -d)
    REALM_URL=$(curl -fsSL https://api.github.com/repos/zhboner/realm/releases/latest | grep "browser_download_url.*realm-x86_64-unknown-linux-gnu.tar.gz" | cut -d '"' -f 4)
    if [ -z "$REALM_URL" ]; then
        REALM_URL="https://github.com/zhboner/realm/releases/latest/download/realm-x86_64-unknown-linux-gnu.tar.gz"
    fi
    curl -fsSL "$REALM_URL" -o "$TMP_DIR/realm.tar.gz"
    tar -xzf "$TMP_DIR/realm.tar.gz" -C /usr/local/bin/
    chmod +x "$REALM_BIN"
    rm -rf "$TMP_DIR"
fi

# 2. 启用系统 BBR 加速与 IP 转发
echo "正在优化网络参数与开启 BBR..."
cat > /etc/sysctl.d/99-duyun-relay.conf <<EOF
net.ipv4.ip_forward = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
EOF
sysctl --system >/dev/null 2>&1 || true

# 3. 配置 Realm 规则
CONFIG_DIR="/etc/realm"
mkdir -p "$CONFIG_DIR"
CONFIG_FILE="$CONFIG_DIR/config.json"

# 如果已有配置文件，通过 jq 或 python 追加/更新规则
if [ -f "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
    NEW_ENDPOINT=$(jq -n \
        --arg listen "0.0.0.0:$LISTEN_PORT" \
        --arg remote "$REMOTE_HOST:$REMOTE_PORT" \
        '{listen: $listen, remote: $remote}')
    jq --arg listen "0.0.0.0:$LISTEN_PORT" --argjson ep "$NEW_ENDPOINT" \
       '.endpoints = [.endpoints[] | select(.listen != $listen)] + [$ep]' \
       "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
else
    cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "level": "warn",
    "output": "/var/log/realm.log"
  },
  "endpoints": [
    {
      "listen": "0.0.0.0:$LISTEN_PORT",
      "remote": "$REMOTE_HOST:$REMOTE_PORT"
    }
  ]
}
EOF
fi

# 4. 创建 systemd 服务
cat > /etc/systemd/system/duyun-relay.service <<EOF
[Unit]
Description=Duyun Relay Port Forwarder (Realm)
After=network.target

[Service]
Type=simple
ExecStart=$REALM_BIN -c $CONFIG_FILE
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable duyun-relay.service
systemctl restart duyun-relay.service

sleep 1

if systemctl is-active --quiet duyun-relay.service; then
    RELAY_IP=$(curl -4 -s ifconfig.me || curl -4 -s ip.sb || echo "中转机公网IP")
    echo ""
    echo "=========================================================="
    echo " ✅ 渡云中转转发配置成功！"
    echo "=========================================================="
    echo " 中转入口: $RELAY_IP:$LISTEN_PORT"
    echo " 转发到落地: $REMOTE_HOST:$REMOTE_PORT"
    echo " 状态: $(systemctl is-active duyun-relay.service)"
    echo ""
    echo " 渡云面板 (duyun88.com) 节点后台填写配置:"
    echo "  - 连接地址 (Host): $RELAY_IP"
    echo "  - 服务端口 (Port): $LISTEN_PORT"
    echo "=========================================================="
else
    echo "❌ 启动失败，请检查日志: journalctl -u duyun-relay.service"
    exit 1
fi
