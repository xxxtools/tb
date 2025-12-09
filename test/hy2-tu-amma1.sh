#!/bin/sh

echo "===================================="
echo "  Hysteria2 + TUIC v5 共存一键安装"
echo "             (Alpine / OpenRC)"
echo "===================================="

# -------------------------------
# 0. 安装依赖（特别是 openssl）
# -------------------------------

如果 ! command -v apk >/dev/null 2>&1; then
    echo "本脚本仅适用于 Alpine 系统（需要 apk 包管理器）"
    exit 1
fi

echo ">>> 安装/检查依赖（openssl / iptables / iproute2 等）..."
apk add --no-cache openssl iproute2 iptables ip6tables net-tools ca-certificates wget >/dev/null

# 生成随机密码的函数（带兜底）
gen_password() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 16 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c 20
    else
        cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c 20
    fi
}

# -------------------------------
# 安装模式选择
# -------------------------------
echo ""
echo "请选择安装模式："
echo "  1) 只安装 Hysteria2"
echo "  2) 只安装 TUIC v5"
echo "  3) 安装 Hysteria2 + TUIC v5（双协议）"
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
# 1. 交互输入：Hysteria2（如果需要）
# -------------------------------
if [ "$INSTALL_MODE" != "2" ]; then
    printf "【Hy2】请输入监听端口 [默认 40443]: "
    read HY_PORT
    [ -z "$HY_PORT" ] && HY_PORT=40443

    printf "【Hy2】请输入节点密码（留空将自动生成）: "
    read HY_PASSWORD
    if [ -z "$HY_PASSWORD" ]; then
        HY_PASSWORD="$(gen_password)"
        if [ -z "$HY_PASSWORD" ]; then
            echo "【Hy2】自动生成密码失败，请重新运行脚本或手动输入密码。"
            exit 1
        fi
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
# 2. 交互输入：TUIC v5（如果需要）
# -------------------------------
if [ "$INSTALL_MODE" != "1" ]; then
    printf "【TUIC】请输入监听端口 [默认 44443]: "
    read TUIC_PORT
    [ -z "$TUIC_PORT" ] && TUIC_PORT=44443

    printf "【TUIC】请输入节点密码（留空将自动生成）: "
    read TUIC_PASSWORD
    if [ -z "$TUIC_PASSWORD" ]; then
        TUIC_PASSWORD="$(gen_password)"
        if [ -z "$TUIC_PASSWORD" ]; then
            echo "【TUIC】自动生成密码失败，请重新运行脚本或手动输入密码。"
            exit 1
        fi
        echo "【TUIC】自动生成密码: $TUIC_PASSWORD"
    fi

    printf "【TUIC】请输入节点名称 [默认 TUIC_Node]: "
    read TUIC_NODE_NAME
    [ -z "$TUIC_NODE_NAME" ] && TUIC_NODE_NAME="TUIC_Node"

    # 默认 SNI：如果同时装双协议，就默认跟 Hy2 一样；如果只装 TUIC，就默认 bing.com
    if [ "$INSTALL_MODE" = "2" ]; then
        DEFAULT_TUIC_SNI="bing.com"
    else
        DEFAULT_TUIC_SNI="$HY_SNI"
    fi

    printf "【TUIC】请输入 SNI 伪装域名 [默认 ${DEFAULT_TUIC_SNI} ]: "
    read TUIC_SNI
    [ -z "$TUIC_SNI" ] && TUIC_SNI="$DEFAULT_TUIC_SNI"

    # TUIC v5 需要 UUID
    TUIC_UUID=$(cat /proc/sys/kernel/random/uuid)
    echo "【TUIC】自动生成 UUID: $TUIC_UUID"
fi

echo ""
echo "=== 开始安装依赖、配置服务 ==="

# -------------------------------
# 3. 停止旧服务（容错处理）
# -------------------------------
pkill -f "/run/hysteria server" 2>/dev/null || true
service hysteria stop 2>/dev/null || true

pkill -f "/run/tuic-server" 2>/dev/null || true
service tuic stop 2>/dev/null || true

# -------------------------------
# 4. 创建 Hysteria2 setup 脚本（如需）
# -------------------------------
if [ "$INSTALL_MODE" != "2" ]; then
cat > /usr/local/bin/setup-hysteria.sh <<EOC
#!/bin/sh
mkdir -p /run

# 下载 Hysteria2 二进制到 /run
if [ ! -x /run/hysteria ]; then
    wget -q -O /run/hysteria https://download.hysteria.network/app/latest/hysteria-linux-amd64
    chmod +x /run/hysteria
fi

# 创建证书
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \\
  -keyout /run/hysteria-key.pem -out /run/hysteria-cert.pem \\
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
iptables -C INPUT -p udp --dport ${HY_PORT} -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport ${HY_PORT} -j ACCEPT

ip6tables -C INPUT -p udp --dport ${HY_PORT} -j ACCEPT 2>/dev/null || \
ip6tables -A INPUT -p udp --dport ${HY_PORT} -j ACCEPT

# 启动 Hy2
/run/hysteria server -c /run/hysteria-config.yaml &
pidof hysteria > /run/hysteria.pid 2>/dev/null || \
pgrep -f "/run/hysteria server" > /run/hysteria.pid 2>/dev/null || true
EOC

chmod +x /usr/local/bin/setup-hysteria.sh
fi

# -------------------------------
# 5. 创建 TUIC setup 脚本（如需）—— 已按“智能保活高稳定版”优化
# -------------------------------
if [ "$INSTALL_MODE" != "1" ]; then
cat > /usr/local/bin/setup-tuic.sh <<EOC
#!/bin/sh
mkdir -p /run

# 下载 TUIC v5 二进制到 /run（Alpine 建议用 musl 版）
如果 [ ! -x /run/tuic-server ]; then
    wget -q -O /run/tuic-server \\
      https://github.com/EAimTY/tuic/releases/download/tuic-server-1.0.0/tuic-server-1.0.0-x86_64-unknown-linux-musl
    chmod +x /run/tuic-server
fi

# 创建自签证书
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \\
  -keyout /run/tuic-key.pem -out /run/tuic-cert.pem \\
  -subj "/CN=${TUIC_SNI}"

# 生成 TUIC v5 配置（智能保活高稳定版）
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
  "max_idle_time": "5m",
  "enable_keepalive": true,
  "keepalive_interval": "30s",
  "max_external_packet_size": 1500,
  "gc_interval": "1m",
  "gc_lifetime": "15m",
  "log_level": "info"
}
EOC2

# 开放 firewall（TUIC UDP 端口）
iptables -C INPUT -p udp --dport ${TUIC_PORT} -j ACCEPT 2>/dev/null || \
iptables -A INPUT -p udp --dport ${TUIC_PORT} -j ACCEPT

ip6tables -C INPUT -p udp --dport ${TUIC_PORT} -j ACCEPT 2>/dev/null || \
ip6tables -A INPUT -p udp --dport ${TUIC_PORT} -j ACCEPT

# 启动 TUIC
/run/tuic-server -c /run/tuic-config.json &
pidof tuic-server > /run/tuic.pid 2>/dev/null || \
pgrep -f "/run/tuic-server" > /run/tuic.pid 2>/dev/null || true
EOC

chmod +x /usr/local/bin/setup-tuic.sh
fi

# -------------------------------
# 6. OpenRC 服务文件 - Hysteria2（如需）
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
fi

# -------------------------------
# 7. OpenRC 服务文件 - TUIC v5（如需）
# -------------------------------
if [ "$INSTALL_MODE" != "1" ]; then
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
fi

# -------------------------------
# 8. 保存防火墙规则
# -------------------------------
/etc/init.d/iptables save 2>/dev/null || true
/etc/init.d/ip6tables save 2>/dev/null || true

# -------------------------------
# 9. 启动服务（按模式）
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
    echo "=== TUIC v5 已安装并启动 ==="
else
    echo "=== Hysteria2 + TUIC v5 已安装并启动 ==="
fi

# -------------------------------
# 10. 输出节点信息（Hy2 + TUIC）
# -------------------------------

PUBLIC_IP=$(
  wget -qO- http://ipv4.ip.sb 2>/dev/null ||
  wget -qO- http://ifconfig.me 2>/dev/null ||
  echo "YOUR.SERVER.IP"
)

[ "$INSTALL_MODE" != "2" ] && HY_ENCODED_NAME=$(printf "%s" "$HY_NODE_NAME" | sed 's/ /%20/g')
[ "$INSTALL_MODE" != "1" ] && TUIC_ENCODED_NAME=$(printf "%s" "$TUIC_NODE_NAME" | sed 's/ /%20/g')

if [ "$INSTALL_MODE" != "2" ]; then
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
    TUIC_URL="tuic://${TUIC_UUID}:${TUIC_PASSWORD}@${PUBLIC_IP}:${TUIC_PORT}?alpn=h3&congestion_control=bbr&insecure=1&sni=${TUIC_SNI}#${TUIC_ENCODED_NAME}"

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
fi

echo ""
echo "在 v2rayN：右键节点 → 从剪贴板导入 URL 即可"
echo ""
