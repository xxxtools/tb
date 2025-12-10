#!/bin/sh

echo "===================================="
echo "  Hysteria2 + TUIC v1.4.5 共存安装"
echo "             (Alpine / OpenRC)"
echo "===================================="

# -------------------------------
# 0. 系统检查 & 安装依赖
# -------------------------------
if ! command -v apk >/dev/null 2>&1; then
    echo "本脚本仅适用于 Alpine 系统（需要 apk 包管理器）"
    exit 1
fi

echo ">>> 安装/检查依赖（openssl / iptables / iproute2 / wget / gcompat 等）..."
apk add --no-cache openssl iproute2 iptables ip6tables net-tools ca-certificates wget gcompat >/dev/null

# 生成随机密码的函数（带兜底）
gen_password_alnum() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 16 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c 20
    else
        cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c 20
    fi
}

gen_password_hex() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 16 2>/dev/null
    else
        cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c 32
    fi
}

echo ""
echo "请选择安装模式："
echo "  1) 只安装 Hysteria2"
echo "  2) 只安装 TUIC v1.4.5"
echo "  3) 安装 Hysteria2 + TUIC v1.4.5（双协议）"
printf "请输入选项 [1-3，默认 3]: "
read INSTALL_MODE
[ -z "$INSTALL_MODE" ] && INSTALL_MODE=3
case "$INSTALL_MODE" in
  1|2|3) ;;
  *)
    echo "输入无效，默认选择 3（双协议）"
    INSTALL_MODE=3
    ;;
esac

# -------------------------------
# 1. 交互输入：Hysteria2（如需）
# -------------------------------
if [ "$INSTALL_MODE" != "2" ]; then
    printf "【Hy2】请输入监听端口 [默认 40443]: "
    read HY_PORT
    [ -z "$HY_PORT" ] && HY_PORT=40443

    printf "【Hy2】请输入节点密码（留空将自动生成）: "
    read HY_PASSWORD
    if [ -z "$HY_PASSWORD" ]; then
        HY_PASSWORD="$(gen_password_alnum)"
        [ -z "$HY_PASSWORD" ] && { echo "【Hy2】自动生成密码失败"; exit 1; }
        echo "【Hy2】自动生成密码: $HY_PASSWORD"
    fi

    printf "【Hy2】请输入节点名称 [默认 Hysteria2_Node]: "
    read HY_NODE_NAME
    [ -z "$HY_NODE_NAME" ] && HY_NODE_NAME="Hysteria2_Node"

    printf "【Hy2】请输入 SNI 伪装域名 [默认 bing.com]: "
    read HY_SNI
    [ -z "$HY_SNI" ] && HY_SNI="bing.com"
fi

echo ""

# -------------------------------
# 2. 交互输入：TUIC v1.4.5（如需）
# -------------------------------
if [ "$INSTALL_MODE" != "1" ]; then
    printf "【TUIC】请输入监听端口 [默认 44443]: "
    read TUIC_PORT
    [ -z "$TUIC_PORT" ] && TUIC_PORT=44443

    printf "【TUIC】请输入节点密码（留空 = 不设密码，和翼龙一致）: "
    read TUIC_PASSWORD
    if [ -z "$TUIC_PASSWORD" ]; then
        echo "【TUIC】使用空密码（URL 格式为 UUID:@IP:PORT ...）"
    else
        echo "【TUIC】将使用你自定义的密码"
    fi

    printf "【TUIC】请输入节点名称 [默认 TUIC_Node]: "
    read TUIC_NODE_NAME
    [ -z "$TUIC_NODE_NAME" ] && TUIC_NODE_NAME="TUIC_Node"

    # 默认 SNI：双协议时默认跟 Hy2 一样，只装 TUIC 则默认 www.bing.com
    if [ "$INSTALL_MODE" = "2" ]; then
        DEFAULT_TUIC_SNI="www.bing.com"
    else
        DEFAULT_TUIC_SNI="$HY_SNI"
    fi

    printf "【TUIC】请输入 SNI 伪装域名 [默认 ${DEFAULT_TUIC_SNI} ]: "
    read TUIC_SNI
    [ -z "$TUIC_SNI" ] && TUIC_SNI="$DEFAULT_TUIC_SNI"

    TUIC_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null)
    [ -z "$TUIC_UUID" ] && TUIC_UUID="$(gen_password_hex)"
    echo "【TUIC】自动生成 UUID: $TUIC_UUID"
fi

echo ""
echo "=== 停止旧服务，准备安装/配置 ==="

# -------------------------------
# 3. 停止旧服务
# -------------------------------
pkill -f "/run/hysteria server" 2>/dev/null || true
service hysteria stop 2>/dev/null || true

pkill -f "/run/tuic-server" 2>/dev/null || true
service tuic stop 2>/dev/null || true

mkdir -p /run

# -------------------------------
# 4. Hysteria2 setup（如需）
# -------------------------------
if [ "$INSTALL_MODE" != "2" ]; then
cat > /usr/local/bin/setup-hysteria.sh <<EOC
#!/bin/sh
mkdir -p /run

if [ ! -x /run/hysteria ]; then
    wget -q -O /run/hysteria https://download.hysteria.network/app/latest/hysteria-linux-amd64
    chmod +x /run/hysteria
fi

openssl req -x509 -newkey rsa:2048 -nodes -days 365 \\
  -keyout /run/hysteria-key.pem -out /run/hysteria-cert.pem \\
  -subj "/CN=${HY_SNI}"

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

iptables -C INPUT -p udp --dport ${HY_PORT} -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport ${HY_PORT} -j ACCEPT

ip6tables -C INPUT -p udp --dport ${HY_PORT} -j ACCEPT 2>/dev/null || \
ip6tables -A INPUT -p udp --dport ${HY_PORT} -j ACCEPT

/run/hysteria server -c /run/hysteria-config.yaml &
echo \$! > /run/hysteria.pid
EOC

chmod +x /usr/local/bin/setup-hysteria.sh
fi

# -------------------------------
# 5. TUIC v1.4.5 setup（后台守护，空密码兼容）（如需）
# -------------------------------
if [ "$INSTALL_MODE" != "1" ]; then
cat > /usr/local/bin/setup-tuic.sh <<EOC
#!/bin/sh
mkdir -p /run

TUIC_BIN="/run/tuic-server"
TUIC_CONF="/run/tuic-server.toml"
CERT_PEM="/run/tuic-cert.pem"
KEY_PEM="/run/tuic-key.pem"

# 下载 tuic v1.4.5 glibc 版（用 gcompat 兼容）
if [ ! -x "\$TUIC_BIN" ]; then
    wget -q -O "\$TUIC_BIN" "https://github.com/Itsusinn/tuic/releases/download/v1.4.5/tuic-server-x86_64-linux"
    chmod +x "\$TUIC_BIN"
fi

# 生成自签证书
if [ ! -f "\$CERT_PEM" ] || [ ! -f "\$KEY_PEM" ]; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \\
      -keyout "\$KEY_PEM" -out "\$CERT_PEM" -subj "/CN=${TUIC_SNI}" -days 365 -nodes >/dev/null 2>&1
    chmod 600 "\$KEY_PEM"
    chmod 644 "\$CERT_PEM"
fi

# 生成配置（贴近你翼龙那份）
cat > "\$TUIC_CONF" <<EOF
log_level = "warn"
server = "0.0.0.0:${TUIC_PORT}"

udp_relay_ipv6 = false
zero_rtt_handshake = true
dual_stack = false
auth_timeout = "8s"
task_negotiation_timeout = "4s"
gc_interval = "8s"
gc_lifetime = "8s"
max_external_packet_size = 8192

[users]
${TUIC_UUID} = "${TUIC_PASSWORD}"

[tls]
certificate = "\$CERT_PEM"
private_key = "\$KEY_PEM"
alpn = ["h3"]

[restful]
addr = "127.0.0.1:${TUIC_PORT}"
secret = "$(gen_password_hex)"
maximum_clients_per_user = 999999999

[quic]
initial_mtu = 1400
min_mtu = 1200
gso = true
pmtu = true
send_window = 33554432
receive_window = 16777216
max_idle_time = "25s"

[quic.congestion_control]
controller = "bbr"
initial_window = 6291456
EOF

iptables -C INPUT -p udp --dport ${TUIC_PORT} -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport ${TUIC_PORT} -j ACCEPT

ip6tables -C INPUT -p udp --dport ${TUIC_PORT} -j ACCEPT 2>/dev/null || \
ip6tables -A INPUT -p udp --dport ${TUIC_PORT} -j ACCEPT

# 后台守护循环：tuic-server 挂了就重启
(
  while true; do
      "\$TUIC_BIN" -c "\$TUIC_CONF"
      echo "tuic-server exited, restart in 5s..." >&2
      sleep 5
  done
) &
echo \$! > /run/tuic.pid
EOC

chmod +x /usr/local/bin/setup-tuic.sh
fi

# -------------------------------
# 6. OpenRC 服务文件
# -------------------------------
if [ "$INSTALL_MODE" != "2" ]; then
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
EOC

chmod +x /etc/init.d/hysteria
rc-update add hysteria default
fi

if [ "$INSTALL_MODE" != "1" ]; then
cat > /etc/init.d/tuic <<'EOC'
#!/sbin/openrc-run
name="tuic"
description="TUIC v1.4.5 service (with guardian loop)"
command="/usr/local/bin/setup-tuic.sh"
command_background="yes"
pidfile="/run/tuic.pid"

depend() {
    need net
    after firewall
    after net-online
}

stop() {
    ebegin "Stopping $name"
    if [ -f /run/tuic.pid ]; then
        kill "$(cat /run/tuic.pid)" 2>/dev/null || true
        rm -f /run/tuic.pid
    fi
    pkill -f "/run/tuic-server" 2>/dev/null || true
    eend $?
}
EOC

chmod +x /etc/init.d/tuic
rc-update add tuic default
fi

# -------------------------------
# 7. 保存防火墙规则
# -------------------------------
/etc/init.d/iptables save 2>/dev/null || true
/etc/init.d/ip6tables save 2>/dev/null || true

# -------------------------------
# 8. 启动服务
# -------------------------------
if [ "$INSTALL_MODE" != "2" ]; then
    service hysteria start
fi

if [ "$INSTALL_MODE" != "1" ]; then
    service tuic start
fi

echo ""
if [ "$INSTALL_MODE" = "1" ]; then
    echo "=== Hysteria2 已安装并启动 ==="
elif [ "$INSTALL_MODE" = "2" ]; then
    echo "=== TUIC v1.4.5 已安装并启动 ==="
else
    echo "=== Hysteria2 + TUIC v1.4.5 已安装并启动 ==="
fi

# -------------------------------
# 9. 输出节点信息
# -------------------------------
PUBLIC_IP=$(
  wget -qO- http://ipv4.ip.sb 2>/dev/null ||
  wget -qO- http://ifconfig.me 2>/dev/null ||
  echo "YOUR.SERVER.IP"
)

if [ "$INSTALL_MODE" != "2" ]; then
    HY_ENCODED_NAME=$(printf "%s" "$HY_NODE_NAME" | sed 's/ /%20/g')
    HY_URL="hysteria2://${HY_PASSWORD}@${PUBLIC_IP}:${HY_PORT}?insecure=1&sni=${HY_SNI}#${HY_ENCODED_NAME}"

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
fi

if [ "$INSTALL_MODE" != "1" ]; then
    TUIC_ENCODED_NAME=$(printf "%s" "$TUIC_NODE_NAME" | sed 's/ /%20/g')
    # 密码为空时，这里会变成 tuic://UUID:@IP:PORT...
    TUIC_URL="tuic://${TUIC_UUID}:${TUIC_PASSWORD}@${PUBLIC_IP}:${TUIC_PORT}?congestion_control=bbr&alpn=h3&allowInsecure=1&sni=${TUIC_SNI}&udp_relay_mode=native&disable_sni=0&reduce_rtt=1&max_udp_relay_packet_size=8192#${TUIC_ENCODED_NAME}"

    echo ""
    echo "=============================="
    echo "   TUIC v1.4.5 节点信息"
    echo "=============================="
    echo "服务器 IP : $PUBLIC_IP"
    echo "节点名称   : $TUIC_NODE_NAME"
    echo "端口       : $TUIC_PORT"
    echo "UUID       : $TUIC_UUID"
    echo "密码       : ${TUIC_PASSWORD:-<空密码>}"
    echo "SNI        : $TUIC_SNI"
    echo ""
    echo "TUIC 导入链接（v2rayN / Shadowrocket 等可用）："
    echo "$TUIC_URL"
    echo "=============================="
fi

echo ""
echo "在 v2rayN：右键节点 → 从剪贴板导入 URL 即可"
echo ""
