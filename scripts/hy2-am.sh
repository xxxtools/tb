#!/bin/sh

echo "=============================="
echo "  Hysteria2 一键安装 - Alpine"
echo "       交互式版启动"
echo "=============================="

# -------------------------------
# 1. 交互输入
# -------------------------------

# 端口
printf "请输入监听端口 [默认 40443]: "
read PORT
[ -z "$PORT" ] && PORT=40443

# 密码
printf "请输入节点密码（留空将自动生成）: "
read PASSWORD
if [ -z "$PASSWORD" ]; then
    PASSWORD=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | head -c 20)
    echo "自动生成密码: $PASSWORD"
fi

# 节点名称
printf "请输入节点名称 [默认 Hysteria2_Node]: "
read NODE_NAME
[ -z "$NODE_NAME" ] && NODE_NAME="Hysteria2_Node"

# SNI 域名
printf "请输入 SNI 伪装域名 [默认 bing.com]: "
read SNI
[ -z "$SNI" ] && SNI="bing.com"


# -------------------------------
# 2. 停止旧服务
# -------------------------------
pkill -f "/run/hysteria server" 2>/dev/null
service hysteria stop 2>/dev/null

# -------------------------------
# 3. 安装依赖
# -------------------------------
apk add --no-cache openssl iproute2 iptables ip6tables net-tools ca-certificates wget

# -------------------------------
# 4. 创建 setup 脚本（开机执行）
# -------------------------------
cat > /usr/local/bin/setup-hysteria.sh <<EOC
#!/bin/sh
mkdir -p /run

# 下载 Hysteria2 二进制到 /run
wget -q -O /run/hysteria https://download.hysteria.network/app/latest/hysteria-linux-amd64
chmod +x /run/hysteria

# 创建证书
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /run/hysteria-key.pem -out /run/hysteria-cert.pem \
  -subj "/CN=${SNI}"

# 生成 Hysteria2 配置
cat > /run/hysteria-config.yaml <<EOC2
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
EOC2

# 开放 firewall
iptables -C INPUT -p udp --dport ${PORT} -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport ${PORT} -j ACCEPT

ip6tables -C INPUT -p udp --dport ${PORT} -j ACCEPT 2>/dev/null || \
ip6tables -A INPUT -p udp --dport ${PORT} -j ACCEPT

# 启动服务
/run/hysteria server -c /run/hysteria-config.yaml &
pidof hysteria > /run/hysteria.pid 2>/dev/null || \
pgrep -f "/run/hysteria server" > /run/hysteria.pid 2>/dev/null || true
EOC

chmod +x /usr/local/bin/setup-hysteria.sh

# -------------------------------
# 5. OpenRC 服务文件
# -------------------------------
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
rc-update add hysteria default

# -------------------------------
# 6. 保存防火墙规则
# -------------------------------
/etc/init.d/iptables save 2>/dev/null
/etc/init.d/ip6tables save 2>/dev/null

# -------------------------------
# 7. 启动服务
# -------------------------------
service hysteria start

echo ""
echo "=== Hysteria2 安装完成，服务已启动 ==="

# -------------------------------
# 8. 输出节点信息（自动生成 v2rayN 链接）
# -------------------------------

PUBLIC_IP=$(
  wget -qO- http://ipv4.ip.sb 2>/dev/null ||
  wget -qO- http://ifconfig.me 2>/dev/null ||
  echo "YOUR.SERVER.IP"
)

ENCODED_NAME=$(printf "%s" "$NODE_NAME" | sed 's/ /%20/g')

NODE_URL="hysteria2://${PASSWORD}@${PUBLIC_IP}:${PORT}?insecure=1&sni=${SNI}#${ENCODED_NAME}"

echo ""
echo "=============================="
echo "   Hysteria2 节点信息（可导入）"
echo "=============================="
echo "服务器 IP : $PUBLIC_IP"
echo "节点名称   : $NODE_NAME"
echo "端口       : $PORT"
echo "密码       : $PASSWORD"
echo "SNI       : $SNI"
echo ""
echo "V2RayN 导入链接（复制整行）："
echo "$NODE_URL"
echo "=============================="
echo ""
echo "在 v2rayN：右键节点 → 从剪贴板导入 URL 即可"
echo ""
