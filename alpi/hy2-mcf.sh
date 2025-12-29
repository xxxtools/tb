#!/bin/sh

ORANGE="\033[38;5;208m"
GREEN="\033[32m"
RESET="\033[0m"

echo "=============================="
echo "  Hysteria2 套 Cloudflare 版"
echo "       Alpine 专用"
echo "=============================="

apk add --no-cache \
  openssl iproute2 iptables ip6tables \
  net-tools ca-certificates wget bash

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) HY_ARCH="amd64" ;;
  aarch64|arm64) HY_ARCH="arm64" ;;
  *) echo "❌ 不支持架构: $ARCH"; exit 1 ;;
esac

echo "检测到架构: $ARCH → $HY_ARCH"

printf "${ORANGE}请输入节点密码（留空自动生成）: ${RESET}"
read PASSWORD
[ -z "$PASSWORD" ] && PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20)"

printf "${ORANGE}请输入节点名称 [默认 CF-Hysteria2]: ${RESET}"
read NODE_NAME
[ -z "$NODE_NAME" ] && NODE_NAME="CF-Hysteria2"

printf "${ORANGE}请输入你的域名（必须走 CF 橙云）: ${RESET}"
read DOMAIN
[ -z "$DOMAIN" ] && echo "❌ 域名不能为空" && exit 1

echo "使用端口: 443（固定 Cloudflare 必须 443）"

pkill -f "/run/hysteria_cf server" 2>/dev/null

cat > /usr/local/bin/setup-hysteria-cf.sh <<EOF
#!/bin/sh
set -e

mkdir -p /run

wget -q -O /run/hysteria_cf \
  https://download.hysteria.network/app/latest/hysteria-linux-${HY_ARCH}
chmod +x /run/hysteria_cf

openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /run/hysteria-cf-key.pem \
  -out /run/hysteria-cf-crt.pem \
  -subj "/CN=${DOMAIN}"

cat > /run/hysteria-cf.yaml <<EOC
listen: ":443"
auth:
  type: password
  password: ${PASSWORD}
tls:
  cert: /run/hysteria-cf-crt.pem
  key: /run/hysteria-cf-key.pem
masquerade:
  type: http
  listen: ":80"
log:
  level: info
EOC

ip6tables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || ip6tables -A INPUT -p tcp --dport 443 -j ACCEPT
ip6tables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || ip6tables -A INPUT -p tcp --dport 80 -j ACCEPT

/run/hysteria_cf server -c /run/hysteria-cf.yaml &
pgrep -f "/run/hysteria_cf server" > /run/hysteria_cf.pid
EOF

chmod +x /usr/local/bin/setup-hysteria-cf.sh

cat > /etc/init.d/hysteria-cf <<'EOF'
#!/sbin/openrc-run
name="hysteria-cf"
description="Hysteria2 CF Service"
command="/usr/local/bin/setup-hysteria-cf.sh"
command_background="yes"
pidfile="/run/hysteria_cf.pid"

depend() {
    need net
    after firewall
}

stop() {
    ebegin "Stopping hysteria-cf"
    pkill -f "/run/hysteria_cf server"
    rm -f /run/hysteria_cf.pid
    eend 0
}
EOF

chmod +x /etc/init.d/hysteria-cf
rc-update add hysteria-cf default
service hysteria-cf restart

ENCODED_NAME="$(printf "%s" "$NODE_NAME" | sed 's/ /%20/g')"

NODE_URL="hysteria2://${PASSWORD}@${DOMAIN}:443?sni=${DOMAIN}&insecure=1#${ENCODED_NAME}"

echo ""
echo "=============================="
echo "   Cloudflare HY2 节点信息"
echo "=============================="
echo "域名       : $DOMAIN"
echo "端口       : 443"
echo "密码       : $PASSWORD"
echo ""
echo "V2RayN 导入链接（复制即可）："
printf "${GREEN}%s${RESET}\n" "$NODE_URL"
echo "=============================="
echo "提示：Cloudflare 里"
echo "DNS -> AAAA 指向你的 IPv6"
echo "必须 开橙云 Proxy"
echo "SSL 模式 = Full"
echo "完成即可使用"
