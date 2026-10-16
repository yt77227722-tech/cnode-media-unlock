#!/bin/bash
# ==============================================================================
# 渡云模式 - 落地节点（Landing Node）全自动一键部署脚本
# 适用：任何海外落地 VPS（香港、台湾、日本、美国、新加坡、欧洲等）
# 包含功能：自动安装 cnode、对接 duyun88.com 面板、挂载对应地区流媒体解锁出站
# ==============================================================================

set -e

NAME=""
NODE_ID=""
REGION="general"
NODE_TYPE="both"
API_HOST="https://duyun88.com"
API_KEY="d1joi2jiojLjkljklHJS1231"
REPO="yt77227722-tech/cnode-media-unlock"

usage() {
    echo "用法: bash deploy_duyun_node.sh -name <名称> -node_id <面板ID> [选项]"
    echo ""
    echo "必填选项:"
    echo "  -name <name>         节点名称 (如 TW-01, HK-01, US-01)"
    echo "  -node_id <id>        渡云面板后端节点 ID (如 1121, 1011)"
    echo ""
    echo "可选选项:"
    echo "  -region <hk|tw|us>   流媒体解锁地区 (默认: general)"
    echo "  -type <anytls|ss|both> 协议类型 (默认: both，同时开 AnyTLS 与 Shadowsocks)"
    echo "  -api_host <url>      面板地址 (默认: https://duyun88.com)"
    echo "  -api_key <key>       面板 API 密钥 (默认内置渡云核心密钥)"
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        -name) NAME="$2"; shift 2 ;;
        -node_id) NODE_ID="$2"; shift 2 ;;
        -region) REGION="$2"; shift 2 ;;
        -type) NODE_TYPE="$2"; shift 2 ;;
        -api_host) API_HOST="$2"; shift 2 ;;
        -api_key) API_KEY="$2"; shift 2 ;;
        *) usage ;;
    esac
done

if [ -z "$NAME" ] || [ -z "$NODE_ID" ]; then
    echo "❌ 缺少必填参数！"
    usage
fi

echo "=========================================================="
echo " 正在启动 渡云模式 落地节点一键部署"
echo " 节点名称: $NAME | 后端 ID: $NODE_ID | 协议: $NODE_TYPE | 地区: $REGION"
echo " 面板地址: $API_HOST"
echo "=========================================================="

# 1. 基础环境
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq curl tar ca-certificates jq
elif command -v yum >/dev/null 2>&1; then
    yum install -y curl tar ca-certificates jq
fi

# 2. 匹配解锁规则 URL
INBOUND_URL="https://raw.githubusercontent.com/$REPO/main/config/inbound.json"
ROUTE_URL="https://raw.githubusercontent.com/$REPO/main/config/route.json"

case "$REGION" in
    hk|HK) OUTBOUND_URL="https://raw.githubusercontent.com/$REPO/main/config/outbound-hk.json" ;;
    tw|TW) OUTBOUND_URL="https://raw.githubusercontent.com/$REPO/main/config/outbound-tw.json" ;;
    us|US) OUTBOUND_URL="https://raw.githubusercontent.com/$REPO/main/config/outbound-us.json" ;;
    *)     OUTBOUND_URL="https://raw.githubusercontent.com/$REPO/main/config/outbound-hk.json" ;;
esac

CNODE_SCRIPT_URL="https://raw.githubusercontent.com/$REPO/main/scripts/cnode.sh"
UPSTREAM_CNODE_URL="https://raw.githubusercontent.com/grrhuipp/cnode/master/scripts/cnode.sh"

# 3. 部署节点
CNODE_RUNNER=$(mktemp /tmp/cnode_deploy.XXXXXX.sh)
if ! curl -fsSL --connect-timeout 10 --retry 2 "$CNODE_SCRIPT_URL" -o "$CNODE_RUNNER" || [ ! -s "$CNODE_RUNNER" ]; then
    echo ">> 优先从个人仓库下载失败，自动回退到官方上游脚本..."
    curl -fsSL --connect-timeout 10 --retry 3 "$UPSTREAM_CNODE_URL" -o "$CNODE_RUNNER"
fi
chmod +x "$CNODE_RUNNER"

if [ "$NODE_TYPE" = "anytls" ] || [ "$NODE_TYPE" = "both" ]; then
    echo ">> 正在配置 AnyTLS 协议..."
    bash "$CNODE_RUNNER" \
      -name "dy-anytls-$NAME" \
      -api_host "$API_HOST" \
      -api_key "$API_KEY" \
      -node_id "$NODE_ID" \
      -node_type anytls \
      -tls_enable true \
      -inbound_url "$INBOUND_URL" \
      -outbound_url "$OUTBOUND_URL" \
      -route_url "$ROUTE_URL"
fi

if [ "$NODE_TYPE" = "ss" ] || [ "$NODE_TYPE" = "both" ]; then
    echo ">> 正在配置 Shadowsocks 协议..."
    bash "$CNODE_RUNNER" \
      -name "dy-ss-$NAME" \
      -api_host "$API_HOST" \
      -api_key "$API_KEY" \
      -node_id "$NODE_ID" \
      -node_type shadowsocks \
      -inbound_url "$INBOUND_URL" \
      -outbound_url "$OUTBOUND_URL" \
      -route_url "$ROUTE_URL"
fi

rm -f "$CNODE_RUNNER"

systemctl restart cnode.service
sleep 2

LOCAL_IP=$(curl -4 -s ifconfig.me || curl -4 -s ip.sb || echo "落地机IP")

echo ""
echo "=========================================================="
echo " 🎉 渡云模式落地节点部署完成！"
echo "=========================================================="
echo " 落地机 IP: $LOCAL_IP"
echo " 节点状态: $(systemctl is-active cnode.service)"
echo ""
echo " 📌 下一步操作指南（对接中转机与面板）："
echo " 1. 在中转机（AWS EC2 / 阿里云）上执行转发命令:"
echo "    bash <(curl -fsSL https://raw.githubusercontent.com/$REPO/main/scripts/deploy_duyun_relay.sh) \\"
echo "      -listen <中转端口,如 65121> -remote $LOCAL_IP:<落地端口,如 55011>"
echo ""
echo " 2. 在渡云面板后台 (duyun88.com/admin) 新增/配置前台节点:"
echo "    - 节点名称: $NAME"
echo "    - 连接地址 (Host): <中转机公网IP>"
echo "    - 服务端口 (Port): <中转端口>"
echo "    - 内部服务端口: <落地端口>"
echo "    - 父节点ID: $NODE_ID"
echo "=========================================================="
