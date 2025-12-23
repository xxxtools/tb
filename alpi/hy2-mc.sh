#!/bin/sh

BLUE="\033[34m"
GREEN="\033[32m"
RESET="\033[0m"

echo "=============================="
echo "  Hysteria2 一键安装 - Alpine"
echo "      最终修复稳定版"
echo "=============================="

# -------------------------------
# 0. 安装依赖（必须最先）
# -------------------------------
apk add --no-cache \
  openssl iproute2 iptables ip6tables \
  net-tools ca-certificates wget

# -------------------------------
# 1. 架构检测
# -------------------------------
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)
    HY_ARCH="amd64"
    ;;
  aarch64|arm64)
    HY_ARCH="arm64"
    ;;
  *)
    echo "❌ 不支持的架构: $ARCH"
    exit 1
    ;;
esac

echo "检测到架构: $ARCH → $HY_ARCH"

# -------------------------------
# 2. 交互输入（改为蓝色高亮）
# -------------------------------
printf "${BLUE}请输入监听端口 [默认 40443]: ${RESET}"
read PORT
[ -z "$PORT" ] && PORT=40443

printf "${BLUE}请输入节点密码（留空自动生成）: ${RESET}"
read PASSWORD
if [ -z "$PASSWORD" ]; then
    PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20)"
    echo "自动生成密码: $PASSWORD"
fi

if [ -z "$PASSWORD" ]; then
    echo "❌ 密码生成失败，终止安装"
    exit 1
fi

printf "${BLUE}请输入节点名称 [默认 Hysteria2_Node]: ${RESET}"
read NODE_NAME
[ -z "$NODE_NAME" ] && NODE_NAME="Hysteria2_Node"

printf "${BLUE}请输入 SNI 伪装域名 [默认 bing.com]: ${RESET}"
read SNI
[ -z "$SNI" ] && SNI="bing.com"

# -------------------------------
# 3. 停止旧服务
# -------------------------------
pkill -f "/run/hysteria server" 2>/dev/null
service hysteria stop 2>/dev/null

# -------------------------------
# 4. setup 脚本
# -------------------------------
cat > /usr/local/bin/setup-hysteria.sh <<EOF
#!/bin/sh
set -e

mkdir -p /run

wget -q -O /run/hysteria \
  https://download.hysteria.network/app/latest/hysteria-linux-${HY_ARCH}
chmod +x /run/hysteria

openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /run/hysteria-key.pem \
  -out /run/hysteria-cert.pem \
  -subj "/CN=${SNI}"

cat > /run/hysteria-config.yaml <<EOC
listen: ":${PORT}"
protocol: udp
auth:
  type: password
  password: ${PASSWORD}
tls:
  sni: ${SNI}
  cert: /run/hysteria-cert.pem
  key: /run/hysteria-key.pem
log:
  level: info
EOC

iptables -C INPUT -p udp --dport ${PORT} -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport ${PORT} -j ACCEPT

ip6tables -C INPUT -p udp --dport ${PORT} -j ACCEPT 2>/dev/null || \
ip6tables -A INPUT -p udp --dport ${PORT} -j ACCEPT

/run/hysteria server -c /run/hysteria-config.yaml &
pgrep -f "/run/hysteria server" > /run/hysteria.pid
EOF

chmod +x /usr/local/bin/setup-hysteria.sh

# -------------------------------
# 5. OpenRC
# -------------------------------
cat > /etc/init.d/hysteria <<'EOF'
#!/sbin/openrc-run
name="hysteria"
description="Hysteria2 Service"
command="/usr/local/bin/setup-hysteria.sh"
command_background="yes"
pidfile="/run/hysteria.pid"

depend() {
    need net
    after firewall
}

stop() {
    ebegin "Stopping hysteria"
    pkill -f "/run/hysteria server"
    rm -f /run/hysteria.pid
    eend 0
}
EOF

chmod +x /etc/init.d/hysteria
rc-update add hysteria default

# -------------------------------
# 6. 防火墙保存
# -------------------------------
/etc/init.d/iptables save 2>/dev/null
/etc/init.d/ip6tables save 2>/dev/null

# -------------------------------
# 7. 启动
# -------------------------------
service hysteria start

# -------------------------------
# 8. 节点信息
# -------------------------------
PUBLIC_IP="$(
  wget -qO- http://ipv4.ip.sb 2>/dev/null ||
  wget -qO- http://ifconfig.me 2>/dev/null ||
  echo "YOUR.SERVER.IP"
)"

ENCODED_NAME="$(printf "%s" "$NODE_NAME" | sed 's/ /%20/g')"

NODE_URL="hysteria2://${PASSWORD}@${PUBLIC_IP}:${PORT}?insecure=1&sni=${SNI}#${ENCODED_NAME}"

echo ""
echo "=============================="
echo "   Hysteria2 节点信息"
echo "=============================="
echo "服务器 IP : $PUBLIC_IP"
echo "端口       : $PORT"
echo "密码       : $PASSWORD"
echo "SNI        : $SNI"
echo ""
echo "V2RayN 导入链接（绿色高亮）："
printf "${GREEN}%s${RESET}\n" "$NODE_URL"
echo "=============================="
