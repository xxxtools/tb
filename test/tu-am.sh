#!/bin/sh

echo "=============================="
echo "  TUIC v5 一键安装 - Alpine"
echo "       交互式版启动"
echo "=============================="

# -------------------------------
# 1. 交互输入
# -------------------------------

# 端口
printf "请输入监听端口 [默认 40443]: "
read PORT
[ -z "$PORT" ] && PORT=40443

# 密码（TUIC 的 password）
printf "请输入节点密码（留空将自动生成）: "
read PASSWORD
if [ -z "$PASSWORD" ]; then
    PASSWORD=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | head -c 20)
    echo "自动生成密码: $PASSWORD"
fi

# 节点名称
printf "请输入节点名称 [默认 TUIC_Node]: "
read NODE_NAME
[ -z "$NODE_NAME" ] && NODE_NAME="TUIC_Node"

# SNI 域名
printf "请输入 SNI 伪装域名 [默认 bing.com]: "
read SNI
[ -z "$SNI" ] && SNI="bing.com"

# TUIC v5 的 User ID（UUID），不问你要，自动生成
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "自动生成 UUID: $UUID"

# -------------------------------
# 2. 停止旧服务
# -------------------------------
pkill -f "/run/tuic-server" 2>/dev/null
service tuic stop 2>/dev/null

# -------------------------------
# 3. 安装依赖
# -------------------------------
apk add --no-cache openssl iproute2 iptables ip6tables net-tools ca-certificates wget

# -------------------------------
# 4. 创建 setup 脚本（开机执行）
# -------------------------------
cat > /usr/local/bin/setup-tuic.sh <<EOC
#!/bin/sh
mkdir -p /run

# 下载 TUIC v5 二进制到 /run（Alpine 用 musl 版本）
wget -q -O /run/tuic-server \
  https://github.com/EAimTY/tuic/releases/download/tuic-server-1.0.0/tuic-server-1.0.0-x86_64-unknown-linux-musl
chmod +x /run/tuic-server

# 创建自签证书
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /run/tuic-key.pem -out /run/tuic-cert.pem \
  -subj "/CN=${SNI}"

# 生成 TUIC v5 配置（JSON）
cat > /run/tuic-config.json <<EOC2
{
  "server": "[::]:${PORT}",
  "users": {
    "${UUID}": "${PASSWORD}"
  },
  "certificate": "/run/tuic-cert.pem",
  "private_key": "/run/tuic-key.pem",
  "congestion_control": "bbr",
  "alpn": ["h3"],
  "udp_relay_ipv6": true,
  "zero_rtt_handshake": false,
  "auth_timeout": "3s",
  "max_idle_time": "10s",
  "max_external_packet_size": 1500,
  "gc_interval": "3s",
  "gc_lifetime": "15s",
  "log_level": "info"
}
EOC2

# 开放防火墙（UDP 端口）
iptables -C INPUT -p udp --dport ${PORT} -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport ${PORT} -j ACCEPT

ip6tables -C INPUT -p udp --dport ${PORT} -j ACCEPT 2>/dev/null || \
ip6tables -A INPUT -p udp --dport ${PORT} -j ACCEPT

# 启动 TUIC
/run/tuic-server -c /run/tuic-config.json &
pidof tuic-server > /run/tuic.pid 2>/dev/null || \
pgrep -f "/run/tuic-server" > /run/tuic.pid 2>/dev/null || true
EOC

chmod +x /usr/local/bin/setup-tuic.sh

# -------------------------------
# 5. OpenRC 服务文件
# -------------------------------
cat > /etc/init.d/tuic <<'EOC'
#!/sbin/openrc-run
name="tuic"
description="TUIC v5 service"
command="/usr/local/bin/setup-tuic.sh"
command_background="yes"
pidfile="/run/tuic.pid"

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
    pkill -f "/run/tuic-server"
    rm -f $pidfile
    eend $?
}
EOC

chmod +x /etc/init.d/tuic
rc-update add tuic default

# -------------------------------
# 6. 保存防火墙规则
# -------------------------------
/etc/init.d/iptables save 2>/dev/null
/etc/init.d/ip6tables save 2>/dev/null

# -------------------------------
# 7. 启动服务
# -------------------------------
service tuic start

echo ""
echo "=== TUIC v5 安装完成，服务已启动 ==="

# -------------------------------
# 8. 输出节点信息（自动生成 v2rayN TUIC 链接）
# -------------------------------

PUBLIC_IP=$(
  wget -qO- http://ipv4.ip.sb 2>/dev/null ||
  wget -qO- http://ifconfig.me 2>/dev/null ||
  echo "YOUR.SERVER.IP"
)

ENCODED_NAME=$(printf "%s" "$NODE_NAME" | sed 's/ /%20/g')

# 标准 TUIC URI：tuic://UUID:PASS@IP:PORT?....#Name
NODE_URL="tuic://${UUID}:${PASSWORD}@${PUBLIC_IP}:${PORT}?alpn=h3&congestion_control=bbr&insecure=1&sni=${SNI}#${ENCODED_NAME"

echo ""
echo "=============================="
echo "   TUIC v5 节点信息（可导入）"
echo "=============================="
echo "服务器 IP  : $PUBLIC_IP"
echo "节点名称    : $NODE_NAME"
echo "端口        : $PORT"
echo "UUID        : $UUID"
echo "密码        : $PASSWORD"
echo "SNI         : $SNI"
echo ""
echo "V2RayN / Shadowrocket TUIC 导入链接（复制整行）："
echo "$NODE_URL"
echo "=============================="
echo ""
echo "在 v2rayN：右键节点 → 从剪贴板导入 URL 即可"
echo ""
