
# 停止旧服务
pkill -f "/run/hysteria server" 2>/dev/null
service hysteria stop 2>/dev/null

# 安装依赖
apk add --no-cache openssl iproute2 iptables ip6tables net-tools ca-certificates curl jq uname

# 自动检测架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        BINARY="hysteria-linux-amd64"
        ;;
    aarch64|arm64)
        BINARY="hysteria-linux-arm64"
        ;;
    *)
        echo "不支持的架构: $ARCH"
        exit 1
        ;;
esac

# 创建 setup 脚本（每次开机都会执行，重建 /run 文件）
cat > /usr/local/bin/setup-hysteria.sh <<EOC
#!/bin/sh
mkdir -p /run

# 下载 Hysteria2 二进制文件到 /run（使用第三方便捷源，支持自动 latest）
wget -q -O /run/hysteria https://download.hysteria.network/app/latest/$BINARY
chmod +x /run/hysteria

# 生成自签名证书（固定 CN=bing.com）
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \\
  -keyout /run/hysteria-key.pem -out /run/hysteria-cert.pem \\
  -subj "/CN=bing.com"

# 创建配置文件（绑定所有 IP，避免写死 IPv6）
cat > /run/hysteria-config.yaml <<EOC2
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
EOC2

# 开放防火墙端口（持久化规则交给 iptables-save）
if command -v iptables >/dev/null; then
    iptables -C INPUT -p udp --dport 40443 -j ACCEPT 2>/dev/null || \\
    iptables -A INPUT -p udp --dport 40443 -j ACCEPT
fi
if command -v ip6tables >/dev/null; then
    ip6tables -C INPUT -p udp --dport 40443 -j ACCEPT 2>/dev/null || \\
    ip6tables -A INPUT -p udp --dport 40443 -j ACCEPT
fi

# 启动 Hysteria2
/run/hysteria server -c /run/hysteria-config.yaml &
pidof hysteria > /run/hysteria.pid 2>/dev/null || \\
pgrep -f "/run/hysteria server" > /run/hysteria.pid 2>/dev/null || true
EOC

chmod +x /usr/local/bin/setup-hysteria.sh

# 创建 OpenRC 服务文件
cat > /etc/init.d/hysteria <<'EOC'
#!/sbin/openrc-run
name="hysteria"
description="Hysteria2 service"
command="/usr/local/bin/setup-hysteria.sh"
command_background="yes"
pidfile="/run/hysteria.pid"

depend() {
    need net
    after firewall
    after net-online
}

start() {
    ebegin "Starting $name"
    $command
    eend $?
}

stop() {
    ebegin "Stopping $name"
    pkill -f "/run/hysteria server"
    rm -f $pidfile
    eend $?
}
EOC

chmod +x /etc/init.d/hysteria

# 添加服务到开机启动（如果已添加则跳过）
rc-update show default | grep -q hysteria || rc-update add hysteria default

# 保存防火墙规则
/etc/init.d/iptables save 2>/dev/null
/etc/init.d/ip6tables save 2>/dev/null

# 启动服务
service hysteria start

echo "=== 安装完成，服务已启动 ==="
ps aux | grep '[h]ysteria'

########################################
# 自动生成 V2RayN 节点链接 #
########################################

# 获取服务器公网 IP
PUBLIC_IP=$(
  curl -s http://ipv4.ip.sb || \
  curl -s http://ifconfig.me || \
  wget -qO- http://ipv4.ip.sb || \
  wget -qO- http://ifconfig.me || \
  echo "YOUR_SERVER_IP"
)

PASSWORD="Wz0FjjnT1Gx9Jqads5Fp3Nbg"
PORT="40443"
SNI="bing.com"
NAME="Hysteria2_Node"

ENCODED_NAME=$(printf "%s" "$NAME" | sed 's/ /%20/g')

NODE_URL="hysteria2://${PASSWORD}@${PUBLIC_IP}:${PORT}?insecure=1&sni=${SNI}#${ENCODED_NAME}"

echo ""
echo "=============================="
echo "     Hysteria2 节点信息"
echo "=============================="
echo "服务器 IP: $PUBLIC_IP"
echo "架构检测: $ARCH ($BINARY)"
echo ""
echo "V2RayN 导入链接（复制整行）："
echo "$NODE_URL"
echo "=============================="
echo ""
echo "在 v2rayN 中：右键节点列表 -> 从剪贴板导入 URL，即可添加此节点。"
echo ""
echo "注意：默认密码不安全！建议安装后手动编辑 /usr/local/bin/setup-hysteria.sh 修改 password 行，然后 service hysteria restart"
