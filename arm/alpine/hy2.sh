```sh
#!/bin/sh
# =====================================================
# Hysteria2 一键安装脚本（ARM / AArch64 / Alpine Linux）
# 适用：Oracle ARM、ARM VPS、Alpine Linux
# 特点：
#  - 自动识别 CPU 架构（arm64 / amd64）
#  - 每次开机自动重建 /run
#  - 自签 TLS（SNI=bing.com）
#  - 自动生成 v2rayN 导入链接
# =====================================================

set -e

PASSWORD="Wz0FjjnT1Gx9Jqads5Fp3Nbg"
PORT="40443"
SNI="bing.com"
NODE_NAME="Hysteria2_ARM"

# 停止旧服务
pkill -f "/run/hysteria server" 2>/dev/null || true
service hysteria stop 2>/dev/null || true

# 安装依赖
apk add --no-cache \
  wget curl openssl ca-certificates \
  iproute2 iptables ip6tables net-tools

# =====================================================
# 创建启动脚本（/run 每次开机都会被清空）
# =====================================================
cat > /usr/local/bin/setup-hysteria.sh <<'EOF'
#!/bin/sh
set -e

mkdir -p /run

# -------- 架构识别 --------
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)
    BIN="hysteria-linux-amd64"
    ;;
  aarch64|arm64)
    BIN="hysteria-linux-arm64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

# -------- 下载 Hysteria2 --------
wget -q -O /run/hysteria https://download.hysteria.network/app/latest/$BIN
chmod +x /run/hysteria

# -------- 生成 TLS 证书 --------
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /run/hysteria-key.pem \
  -out /run/hysteria-cert.pem \
  -subj "/CN=bing.com"

# -------- 配置文件 --------
cat > /run/hysteria-config.yaml <<EOC
listen: ":40443"
protocol: udp
auth:
  type: password
  password: Wz0FjjnT1Gx9Jqads5Fp3Nbg
tls:
  sni: bing.com
  cert: /run/hysteria-cert.pem
  key: /run/hysteria-key.pem
log:
  level: info
EOC

# -------- 防火墙 --------
iptables -C INPUT -p udp --dport 40443 -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport 40443 -j ACCEPT

ip6tables -C INPUT -p udp --dport 40443 -j ACCEPT 2>/dev/null || \
ip6tables -A INPUT -p udp --dport 40443 -j ACCEPT

# -------- 启动 --------
/run/hysteria server -c /run/hysteria-config.yaml &
echo $! > /run/hysteria.pid
EOF

chmod +x /usr/local/bin/setup-hysteria.sh

# =====================================================
# OpenRC 服务
# =====================================================
cat > /etc/init.d/hysteria <<'EOF'
#!/sbin/openrc-run
name="hysteria"
command="/usr/local/bin/setup-hysteria.sh"
command_background="yes"
pidfile="/run/hysteria.pid"

depend() {
  need net
  after firewall
}

stop() {
  pkill -f "/run/hysteria server" 2>/dev/null || true
}
EOF

chmod +x /etc/init.d/hysteria

rc-update add hysteria default

/etc/init.d/iptables save 2>/dev/null || true
/etc/init.d/ip6tables save 2>/dev/null || true

service hysteria restart

# =====================================================
# 生成 v2rayN 节点链接
# =====================================================
PUBLIC_IP=$(curl -4 -s https://ipv4.ip.sb || echo YOUR_SERVER_IP)
ENC_NAME=$(printf "%s" "$NODE_NAME" | sed 's/ /%20/g')

NODE_URL="hysteria2://${PASSWORD}@${PUBLIC_IP}:${PORT}?insecure=1&sni=${SNI}#${ENC_NAME}"

echo ""
echo "=============================="
echo " Hysteria2 ARM 节点信息"
echo "=============================="
echo "服务器 IP: $PUBLIC_IP"
echo "端口: $PORT"
echo "密码: $PASSWORD"
echo "SNI: $SNI"
echo ""
echo "v2rayN 导入链接："
echo "$NODE_URL"
echo "=============================="
```
