#!/bin/bash
# ==============================================================================
# 流媒体解锁中转网关（Media Unlock Gateway）独立一键部署脚本
# 适用场景：当 media-*.9527app.site 失效，或需要在任何一台具有原生解锁能力的 VPS 上
# 快速建立 2052 端口的流媒体中转网关时使用。
# ==============================================================================

set -e

PORT="${1:-2052}"
UUID="bf417eb3-d283-5487-b6ad-9a9be278be8a"
INSTALL_DIR="/opt/media-gateway"

echo "=========================================================="
echo " 正在部署流媒体解锁中转网关 (Media Unlock Gateway)"
echo " 监听端口: $PORT | 协议: VMess+WS | UUID: $UUID"
echo "=========================================================="

# 1. 安装基础依赖
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq curl jq
elif command -v yum >/dev/null 2>&1; then
    yum install -y curl jq
fi

mkdir -p "$INSTALL_DIR"

# 2. 安装 Xray 官方内核（轻量、稳定、低内存）
if [ ! -f "$INSTALL_DIR/xray" ]; then
    echo "正在下载 Xray 内核..."
    TMP_DIR=$(mktemp -d)
    LATEST_XRAY_URL=$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r '.assets[] | select(.name == "Xray-linux-64.zip") | .browser_download_url')
    if [ -z "$LATEST_XRAY_URL" ] || [ "$LATEST_XRAY_URL" = "null" ]; then
        LATEST_XRAY_URL="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
    fi
    curl -fsSL "$LATEST_XRAY_URL" -o "$TMP_DIR/xray.zip"
    
    if command -v unzip >/dev/null 2>&1; then
        unzip -q "$TMP_DIR/xray.zip" -d "$INSTALL_DIR"
    else
        if command -v apt-get >/dev/null 2>&1; then apt-get install -y -qq unzip; elif command -v yum >/dev/null 2>&1; then yum install -y unzip; fi
        unzip -q "$TMP_DIR/xray.zip" -d "$INSTALL_DIR"
    fi
    chmod +x "$INSTALL_DIR/xray"
    rm -rf "$TMP_DIR"
fi

# 3. 写入解锁网关配置（完全对齐 inbound.json 与自由直连出站）
cat > "$INSTALL_DIR/config.json" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $PORT,
      "listen": "0.0.0.0",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIP"
      }
    }
  ]
}
EOF

# 4. 创建并启动 systemd 服务
cat > /etc/systemd/system/media-gateway.service <<EOF
[Unit]
Description=Media Unlock Gateway (Xray)
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/xray run -config $INSTALL_DIR/config.json
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable media-gateway.service
systemctl restart media-gateway.service

sleep 1

if systemctl is-active --quiet media-gateway.service; then
    SERVER_IP=$(curl -4 -s ifconfig.me || curl -4 -s ip.sb || echo "你的服务器IP")
    echo ""
    echo "=========================================================="
    echo " ✅ 解锁网关部署成功！"
    echo "=========================================================="
    echo " 网关 IP: $SERVER_IP"
    echo " 监听端口: $PORT"
    echo " 服务状态: $(systemctl is-active media-gateway.service)"
    echo ""
    echo " 恢复指南:"
    echo " 1. 如果你在 Cloudflare / DNS 控制域名："
    echo "    直接将 media-*.9527app.site（或你自己的域名）A 记录解析到 $SERVER_IP"
    echo " 2. 全网落地机无需修改配置即可恢复解锁！"
    echo "=========================================================="
else
    echo "❌ 启动失败，请检查 journalctl -u media-gateway.service"
    exit 1
fi
