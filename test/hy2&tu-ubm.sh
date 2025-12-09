#!/bin/sh

export DEBIAN_FRONTEND=noninteractive

echo "===================================="
echo "  Hysteria2 + TUIC v5 共存一键安装"
echo "           (Ubuntu / Debian)"
echo "===================================="

# -------------------------------
# 1. 交互输入：Hysteria2
# -------------------------------

printf "【Hy2】请输入监听端口 [默认 40443]: "
read HY_PORT
[ -z "$HY_PORT" ] && HY_PORT=40443

printf "【Hy2】请输入节点密码（留空将自动生成）: "
read HY_PASSWORD
if [ -z "$HY_PASSWORD" ]; then
    HY_PASSWORD=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | head -c 20)
    echo "【Hy2】自动生成密码: $HY_PASSWORD"
fi

printf "【Hy2】请输入节点名称 [默认 Hysteria2_Node]: "
read HY_NODE_NAME
[ -z "$HY_NODE_NAME" ] && HY_NODE_NAME="Hysteria2_Node"

printf "【Hy2】请输入 SNI 伪装域名 [默认 bing.com]: "
read HY_SNI
[ -z "$HY_SNI" ] && HY_SNI="bing.com"

echo ""

# -------------------------------
# 2. 交互输入：TUIC v5
# -------------------------------

printf "【TUIC】请输入监听端口 [默认 44443]: "
read TUIC_PORT
[ -z "$TUIC_PORT" ] && TUIC_PORT=44443

printf "【TUIC】请输入节点密码（留空将自动生成）: "
read TUIC_PASSWORD
if [ -z "$TUIC_PASSWORD" ]; then
    TUIC_PASSWORD=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | head -c 20)
    echo "【TUIC】自动生成密码: $TUIC_PASSWORD"
fi

printf "【TUIC】请输入节点名称 [默认 TUIC_Node]: "
read TUIC_NODE_NAME
[ -z "$TUIC_NODE_NAME" ] && TUIC_NODE_NAME="TUIC_Node"

printf "【TUIC】请输入 SNI 伪装域名 [默认 与 Hy2 相同: $HY_SNI ]: "
read TUIC_SNI
[ -z "$TUIC_SNI" ] && TUIC_SNI="$HY_SNI"

# TUIC v5 需要 UUID
TUIC_UUID=$(cat /proc/sys/kernel/random/uuid)
echo "【TUIC】自动生成 UUID: $TUIC_UUID"

echo ""
echo "=== 开始安装依赖、配置服务（Ubuntu/Debian） ==="

# -------------------------------
# 3. 停止旧服务
# -------------------------------
pkill -f "/run/hysteria server" 2>/dev/null
systemctl stop hysteria 2>/dev/null || true

pkill -f "/run/tuic-server" 2>/dev/null
systemctl stop tuic 2>/dev/null || true

# -------------------------------
# 4. 安装依赖
# -------------------------------
apt update
apt install -y \
  wget \
  curl \
  openssl \
  iproute2 \
  iptables \
  net-tools \
  iptables-persistent \
  ca-certificates

# -------------------------------
# 5. 创建 Hysteria2 setup 脚本
# -------------------------------
cat > /usr/local/bin/setup-hysteria.sh <<EOC
#!/bin/sh
mkdir -p /run

# 下载 Hysteria2 二进制到 /run（使用官方 release）
wget -q -O /run/hysteria \
  https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64
chmod +x /run/hysteria

# 创建证书
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /run/hysteria-key.pem -out /run/hysteria-cert.pem \
  -subj "/CN=${HY_SNI}"

# 生成 Hysteria2 配置
cat > /run/hysteria-config.yaml <<EOC2
listen: ":${HY_PORT}"
protocol: udp
auth:
  type: password
  password: ${HY_PASSWORD}
tls:
  sni: ${HY_SNI}
  cert: /run/hysteria-cert.pem
  key: /run/hysteria-key.pem
log:
  level: info
EOC2

# 开放 firewall（Hy2 UDP 端口）
if command -v iptables >/dev/null; then
  iptables -C INPUT -p udp --dport ${HY_PORT} -j ACCEPT 2>/dev/null || \
  iptables -A INPUT -p udp --dport ${HY_PORT} -j ACCEPT
fi

if command -v ip6tables >/dev/null; then
  ip6tables -C INPUT -p udp --dport ${HY_PORT} -j ACCEPT 2>/dev/null || \
  ip6tables -A INPUT -p udp --dport ${HY_PORT} -j ACCEPT
fi

# 启动 Hy2
/run/hysteria server -c /run/hysteria-config.yaml &
pidof hysteria > /run/hysteria.pid 2>/dev/null || \
pgrep -f "/run/hysteria server" > /run/hysteria.pid 2>/dev/null || true
EOC

chmod +x /usr/local/bin/setup-hysteria.sh

# -------------------------------
# 6. 创建 TUIC v5 setup 脚本
# -------------------------------
cat > /usr/local/bin/setup-tuic.sh <<EOC
#!/bin/sh
mkdir -p /run

# 下载 TUIC v5 二进制到 /run（GNU 版，适配 Debian/Ubuntu）
wget -q -O /run/tuic-server \
  https://github.com/EAimTY/tuic/releases/download/tuic-server-1.0.0/tuic-server-1.0.0-x86_64-unknown-linux-gnu
chmod +x /run/tuic-server

# 创建自签证书
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /run/tuic-key.pem -out /run/tuic-cert.pem \
  -subj "/CN=${TUIC_SNI}"

# 生成 TUIC v5 配置
cat > /run/tuic-config.json <<EOC2
{
  "server": "[::]:${TUIC_PORT}",
  "users": {
    "${TUIC_UUID}": "${TUIC_PASSWORD}"
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

# 开放 firewall（TUIC UDP 端口）
if command -v iptables >/dev/null; then
  iptables -C INPUT -p udp --dport ${TUIC_PORT} -j ACCEPT 2>/dev/null || \
  iptables -A INPUT -p udp --dport ${TUIC_PORT} -j ACCEPT
fi

if command -v ip6tables >/dev/null; then
  ip6tables -C INPUT -p udp --dport ${TUIC_PORT} -j ACCEPT 2>/dev/null || \
  ip6tables -A INPUT -p udp --dport ${TUIC_PORT} -j ACCEPT
fi

# 启动 TUIC
/run/tuic-server -c /run/tuic-config.json &
pidof tuic-server > /run/tuic.pid 2>/dev/null || \
pgrep -f "/run/tuic-server" > /run/tuic.pid 2>/dev/null || true
EOC

chmod +x /usr/local/bin/setup-tuic.sh

# -------------------------------
# 7. systemd 服务 - Hysteria2
# -------------------------------
cat > /etc/systemd/system/hysteria.service <<'EOC'
[Unit]
Description=Hysteria2 service
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/run/hysteria.pid
ExecStart=/usr/local/bin/setup-hysteria.sh
ExecStop=/bin/sh -c 'pkill -f "/run/hysteria server" || true; rm -f /run/hysteria.pid || true'
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOC

# -------------------------------
# 8. systemd 服务 - TUIC v5
# -------------------------------
cat > /etc/systemd/system/tuic.service <<'EOC'
[Unit]
Description=TUIC v5 service
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/run/tuic.pid
ExecStart=/usr/local/bin/setup-tuic.sh
ExecStop=/bin/sh -c 'pkill -f "/run/tuic-server" || true; rm -f /run/tuic.pid || true'
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOC

# -------------------------------
# 9. 重新加载 systemd & 开机自启
# -------------------------------
systemctl daemon-reload
systemctl enable hysteria tuic

# -------------------------------
# 10. 保存防火墙规则（持久化）
# -------------------------------
if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
elif command -v service >/dev/null 2>&1; then
    service netfilter-persistent save 2>/dev/null || true
fi

# -------------------------------
# 11. 启动服务
# -------------------------------
systemctl start hysteria
systemctl start tuic

echo ""
echo "=== Hysteria2 + TUIC v5 已安装并启动 (Ubuntu/Debian) ==="
systemctl --no-pager --full status hysteria 2>/dev/null | head -n 10
systemctl --no-pager --full status tuic 2>/dev/null | head -n 10

# -------------------------------
# 12. 输出节点信息（Hy2 + TUIC）
# -------------------------------

PUBLIC_IP=$(
  curl -s http://ipv4.ip.sb 2>/dev/null ||
  curl -s http://ifconfig.me 2>/dev/null ||
  echo "YOUR.SERVER.IP"
)

HY_ENCODED_NAME=$(printf "%s" "$HY_NODE_NAME" | sed 's/ /%20/g')
TUIC_ENCODED_NAME=$(printf "%s" "$TUIC_NODE_NAME" | sed 's/ /%20/g')

HY_URL="hysteria2://${HY_PASSWORD}@${PUBLIC_IP}:${HY_PORT}?insecure=1&sni=${HY_SNI}#${HY_ENCODED_NAME}"
TUIC_URL="tuic://${TUIC_UUID}:${TUIC_PASSWORD}@${PUBLIC_IP}:${TUIC_PORT}?alpn=h3&congestion_control=bbr&insecure=1&sni=${TUIC_SNI}#${TUIC_ENCODED_NAME}"

echo ""
echo "=============================="
echo "   Hysteria2 节点信息"
echo "=============================="
echo "服务器 IP : $PUBLIC_IP"
echo "节点名称   : $HY_NODE_NAME"
echo "端口       : $HY_PORT"
echo "密码       : $HY_PASSWORD"
echo "SNI        : $HY_SNI"
echo ""
echo "V2RayN 导入链接（复制整行）："
echo "$HY_URL"
echo "=============================="
echo ""
echo "=============================="
echo "   TUIC v5 节点信息"
echo "=============================="
echo "服务器 IP : $PUBLIC_IP"
echo "节点名称   : $TUIC_NODE_NAME"
echo "端口       : $TUIC_PORT"
echo "UUID       : $TUIC_UUID"
echo "密码       : $TUIC_PASSWORD"
echo "SNI        : $TUIC_SNI"
echo ""
echo "TUIC 导入链接（v2rayN / Shadowrocket 等可用）："
echo "$TUIC_URL"
echo "=============================="
echo ""
echo "在 v2rayN：右键节点 → 从剪贴板导入 URL 即可"
echo ""
