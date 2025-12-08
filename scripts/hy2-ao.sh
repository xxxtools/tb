#!/bin/sh

# 停止旧服务
pkill -f "/run/hysteria server" 2>/dev/null
service hysteria stop 2>/dev/null

# 安装依赖
apk add --no-cache openssl iproute2 iptables ip6tables net-tools

# 创建 setup 脚本（每次开机都会执行，重建 /run 文件）
cat > /usr/local/bin/setup-hysteria.sh <<'EOC'
#!/bin/sh
mkdir -p /run

# 下载 Hysteria2 二进制文件到 /run
wget -q -O /run/hysteria https://download.hysteria.network/app/latest/hysteria-linux-amd64
chmod +x /run/hysteria

# 生成自签名证书（固定 CN=bing.com）
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /run/hysteria-key.pem -out /run/hysteria-cert.pem \
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
    iptables -C INPUT -p udp --dport 40443 -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p udp --dport 40443 -j ACCEPT
fi
if command -v ip6tables >/dev/null; then
    ip6tables -C INPUT -p udp --dport 40443 -j ACCEPT 2>/dev/null || \
    ip6tables -A INPUT -p udp --dport 40443 -j ACCEPT
fi

# 启动 Hysteria2
/run/hysteria server -c /run/hysteria-config.yaml &
pidof hysteria > /run/hysteria.pid
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

# 添加服务到开机启动
rc-update add hysteria default

# 保存防火墙规则（保证 reboot 后端口开放）
/etc/init.d/iptables save 2>/dev/null
/etc/init.d/ip6tables save 2>/dev/null

# 启动服务
service hysteria start

echo "=== 安装完成，服务已启动 ==="
ps aux | grep '[h]ysteria'
