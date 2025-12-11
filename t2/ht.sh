#!/bin/sh

echo "===================================="
echo "  Hysteria2 + sing-box TUIC 共存一键安装（精简稳定版）"
echo "             (Alpine / OpenRC)"
echo "===================================="

# -------------------------------
# 0. 基本检查 & 安装依赖
# -------------------------------
if ! command -v apk >/dev/null 2>&1; then
  echo "本脚本仅适用于 Alpine（需要 apk 包管理器）"
  exit 1
fi

echo ">>> 安装/检查依赖（openssl / iptables / iproute2 / wget / tar 等）..."
apk add --no-cache openssl iproute2 iptables ip6tables ca-certificates wget tar >/dev/null 2>&1

# -------------------------------
# 0.1 自动安装 sing-box（如果系统里没有）
# -------------------------------
if ! command -v sing-box >/dev/null 2>&1; then
  echo ">>> 未检测到 sing-box，开始自动安装 v1.12.12 ..."

  ARCH="$(uname -m)"
  SB_VER="1.12.12"

  case "$ARCH" in
    x86_64|amd64)  SB_FILE="sing-box-${SB_VER}-linux-amd64.tar.gz" ;;
    aarch64|arm64) SB_FILE="sing-box-${SB_VER}-linux-arm64.tar.gz" ;;
    *)
      echo "当前架构: $ARCH 暂不支持自动安装 sing-box，请手动安装。"
      exit 1
      ;;
  esac

  SB_URL="https://github.com/SagerNet/sing-box/releases/download/v${SB_VER}/${SB_FILE}"
  TMP_DIR="/run/sing-box-install-$$"
  mkdir -p "$TMP_DIR"

  echo ">>> 下载 sing-box：$SB_URL"
  if ! wget -q -O "${TMP_DIR}/${SB_FILE}" "$SB_URL"; then
    echo "下载 sing-box 失败。"
    rm -rf "$TMP_DIR"
    exit 1
  fi

  echo ">>> 解压 sing-box ..."
  cd "$TMP_DIR" || exit 1
  if ! tar -xf "$SB_FILE"; then
    echo "解压 sing-box 失败。"
    rm -rf "$TMP_DIR"
    exit 1
  fi

  SB_BIN_PATH="$(find "$TMP_DIR" -maxdepth 3 -type f -name 'sing-box' | head -n1)"
  if [ -z "$SB_BIN_PATH" ]; then
    echo "未在压缩包中找到 sing-box 可执行文件。"
    rm -rf "$TMP_DIR"
    exit 1
  fi

  echo ">>> 安装 sing-box 到 /usr/local/bin/sing-box"
  mv "$SB_BIN_PATH" /usr/local/bin/sing-box
  chmod +x /usr/local/bin/sing-box

  cd /
  rm -rf "$TMP_DIR"
  echo ">>> sing-box 安装完成。"
else
  echo ">>> 检测到 sing-box 已安装，跳过安装步骤。"
fi

# 再确认一次
if ! command -v sing-box >/dev/null 2>&1; then
  echo "错误：仍未检测到 sing-box，请手动安装后再运行本脚本。"
  exit 1
fi

# -------------------------------
# 1. 交互输入：Hysteria2
# -------------------------------
printf "【Hy2】请输入监听端口 [默认 40443]: "
read HY_PORT
[ -z "$HY_PORT" ] && HY_PORT=40443

printf "【Hy2】请输入节点密码（留空将自动生成）: "
read HY_PASSWORD
if [ -z "$HY_PASSWORD" ]; then
  HY_PASSWORD=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | head -n 1 | cut -c1-20)
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
# 2. 交互输入：TUIC（sing-box 内核）
# -------------------------------
printf "【TUIC】请输入监听端口 [默认 44443]: "
read TUIC_PORT
[ -z "$TUIC_PORT" ] && TUIC_PORT=44443

printf "【TUIC】请输入节点密码（留空将自动生成）: "
read TUIC_PASSWORD
if [ -z "$TUIC_PASSWORD" ]; then
  TUIC_PASSWORD=$(openssl rand -hex 16)
  echo "【TUIC】自动生成密码: $TUIC_PASSWORD"
fi

printf "【TUIC】请输入节点名称 [默认 TUIC_Node]: "
read TUIC_NODE_NAME
[ -z "$TUIC_NODE_NAME" ] && TUIC_NODE_NAME="TUIC_Node"

printf "【TUIC】请输入 SNI 伪装域名 [默认 与 Hy2 相同: $HY_SNI ]: "
read TUIC_SNI
[ -z "$TUIC_SNI" ] && TUIC_SNI="$HY_SNI"

TUIC_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null)
[ -z "$TUIC_UUID" ] && TUIC_UUID="00000000-0000-0000-0000-000000000000"
echo "【TUIC】自动生成 UUID: $TUIC_UUID"

echo ""
echo "=== 停止旧服务，准备安装/配置 ==="

# -------------------------------
# 3. 停止旧服务
# -------------------------------
pkill -f "/run/hysteria server" 2>/dev/null
pkill -f "sb-tuic.json" 2>/dev/null
service hysteria stop 2>/dev/null
service tuic stop 2>/dev/null

rm -f /run/hysteria-config.yaml /run/sb-tuic.json /run/hysteria.pid /run/tuic.pid
mkdir -p /run

# -------------------------------
# 4. 创建 Hysteria2 setup 脚本
# -------------------------------
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

iptables -C INPUT -p udp --dport ${HY_PORT} -j ACCEPT 2>/dev/null || \\
iptables -A INPUT -p udp --dport ${HY_PORT} -j ACCEPT

ip6tables -C INPUT -p udp --dport ${HY_PORT} -j ACCEPT 2>/dev/null || \\
ip6tables -A INPUT -p udp --dport ${HY_PORT} -j ACCEPT

/run/hysteria server -c /run/hysteria-config.yaml &
echo \$! > /run/hysteria.pid
EOC

chmod +x /usr/local/bin/setup-hysteria.sh

# -------------------------------
# 5. 创建 TUIC（sing-box） setup 脚本
# -------------------------------
cat > /usr/local/bin/setup-tuic.sh <<EOC
#!/bin/sh
mkdir -p /run

if ! command -v sing-box >/dev/null 2>&1; then
  echo "错误：未找到 sing-box 命令"
  exit 1
fi

openssl req -x509 -newkey rsa:2048 -nodes -days 365 \\
  -keyout /run/tuic-key.pem -out /run/tuic-cert.pem \\
  -subj "/CN=${TUIC_SNI}"

cat > /run/sb-tuic.json <<EOC2
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "::",
      "listen_port": ${TUIC_PORT},
      "users": [
        {
          "uuid": "${TUIC_UUID}",
          "password": "${TUIC_PASSWORD}"
        }
      ],
      "congestion_control": "bbr",
      "auth_timeout": "8s",
      "zero_rtt_handshake": false,
      "heartbeat": "30s",
      "tls": {
        "enabled": true,
        "server_name": "${TUIC_SNI}",
        "certificate_path": "/run/tuic-cert.pem",
        "key_path": "/run/tuic-key.pem",
        "insecure": true
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOC2

iptables -C INPUT -p udp --dport ${TUIC_PORT} -j ACCEPT 2>/dev/null || \\
iptables -A INPUT -p udp --dport ${TUIC_PORT} -j ACCEPT

ip6tables -C INPUT -p udp --dport ${TUIC_PORT} -j ACCEPT 2>/dev/null || \\
ip6tables -A INPUT -p udp --dport ${TUIC_PORT} -j ACCEPT

sing-box run -c /run/sb-tuic.json &
echo \$! > /run/tuic.pid
EOC

chmod +x /usr/local/bin/setup-tuic.sh

# -------------------------------
# 6. OpenRC 服务文件
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
  ebegin "Starting hysteria"
  $command
  eend $?
}

stop() {
  ebegin "Stopping hysteria"
  pkill -f "/run/hysteria server" 2>/dev/null
  rm -f $pidfile
  eend $?
}
EOC

chmod +x /etc/init.d/hysteria
rc-update add hysteria default 2>/dev/null

cat > /etc/init.d/tuic <<'EOC'
#!/sbin/openrc-run
name="tuic"
description="TUIC (sing-box) service"
command="/usr/local/bin/setup-tuic.sh"
command_background="yes"
pidfile="/run/tuic.pid"

depend() {
  need net
  after firewall
  after net-online
}

start() {
  ebegin "Starting tuic"
  $command
  eend $?
}

stop() {
  ebegin "Stopping tuic"
  if [ -f /run/tuic.pid ]; then
    kill "$(cat /run/tuic.pid)" 2>/dev/null || true
    rm -f /run/tuic.pid
  fi
  pkill -f "sb-tuic.json" 2>/dev/null || true
  eend $?
}
EOC

chmod +x /etc/init.d/tuic
rc-update add tuic default 2>/dev/null

# -------------------------------
# 7. 保存防火墙规则 & 启动
# -------------------------------
/etc/init.d/iptables save 2>/dev/null
/etc/init.d/ip6tables save 2>/dev/null

service hysteria restart
service tuic restart

echo ""
echo "=== Hysteria2 + sing-box TUIC 已安装并启动（精简稳定版） ==="

PUBLIC_IP=$(
  wget -qO- http://ipv4.ip.sb 2>/dev/null ||
  wget -qO- http://ifconfig.me 2>/dev/null ||
  echo "YOUR.SERVER.IP"
)

HY_ENCODED_NAME=$(printf "%s" "$HY_NODE_NAME" | sed 's/ /%20/g')
TUIC_ENCODED_NAME=$(printf "%s" "$TUIC_NODE_NAME" | sed 's/ /%20/g')

HY_URL="hysteria2://${HY_PASSWORD}@${PUBLIC_IP}:${HY_PORT}?insecure=1&sni=${HY_SNI}#${HY_ENCODED_NAME}"
TUIC_URL="tuic://${TUIC_UUID}:${TUIC_PASSWORD}@${PUBLIC_IP}:${TUIC_PORT}?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=${TUIC_SNI}&allowInsecure=1#${TUIC_ENCODED_NAME}"

echo "=============================="
echo "   Hysteria2 节点信息"
echo "=============================="
echo "服务器 IP : $PUBLIC_IP"
echo "节点名称   : $HY_NODE_NAME"
echo "端口       : $HY_PORT"
echo "密码       : $HY_PASSWORD"
echo "SNI        : $HY_SNI"
echo ""
echo "V2RayN 导入链接："
echo "$HY_URL"
echo "=============================="
echo ""
echo "=============================="
echo "   TUIC (sing-box) 节点信息"
echo "=============================="
echo "服务器 IP : $PUBLIC_IP"
echo "节点名称   : $TUIC_NODE_NAME"
echo "端口       : $TUIC_PORT"
echo "UUID       : $TUIC_UUID"
echo "密码       : $TUIC_PASSWORD"
echo "SNI        : $TUIC_SNI"
echo ""
echo "TUIC 导入链接："
echo "$TUIC_URL"
echo "=============================="
echo ""
echo "在 v2rayN：右键节点 → 从剪贴板导入 URL 即可"
echo ""
