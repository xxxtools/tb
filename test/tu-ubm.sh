#!/bin/sh

# 交互式多节点 TUIC v5 安装脚本（Ubuntu / Debian）
# 每个节点都会创建一个独立的 systemd 服务：tuic-<节点名处理后>.service

export DEBIAN_FRONTEND=noninteractive

echo "=== TUIC v5 多节点安装 / 管理脚本（Ubuntu / Debian）==="

# ==========================
# 1. 安装依赖
# ==========================
echo "[*] 安装依赖..."
apt update
apt install -y wget curl openssl iproute2 iptables net-tools iptables-persistent

# ==========================
# 2. 安装 TUIC v5 服务端二进制（全局共用）
# ==========================
if [ ! -x /usr/local/bin/tuic-server ]; then
  echo "[*] 下载 tuic-server 到 /usr/local/bin/tuic-server ..."
  wget -q -O /usr/local/bin/tuic-server \
    "https://github.com/tuic-protocol/tuic/releases/download/tuic-server-1.0.0/tuic-server-1.0.0-x86_64-unknown-linux-gnu"
  chmod +x /usr/local/bin/tuic-server
else
  echo "[*] 已检测到 /usr/local/bin/tuic-server，跳过下载。"
fi

# 配置目录
TUIC_DIR="/etc/tuic"
mkdir -p "$TUIC_DIR"

# 获取服务器公网 IP（后面用来生成节点链接）
PUBLIC_IP=$(curl -s ipv4.ip.sb || curl -s ifconfig.me || echo "YOUR_SERVER_IP")

echo "[*] 检测到公网 IP: $PUBLIC_IP"
echo ""

create_node() {
  echo "----------------------------------------"
  echo "创建一个新的 TUIC v5 节点"
  echo "----------------------------------------"

  # 端口
  printf "请输入监听端口 [默认 40443]: "
  read PORT
  if [ -z "$PORT" ]; then
    PORT="40443"
  fi

  # 用户 UUID（TUIC v5 需要 uuid + password）
  printf "请输入用户 UUID（留空则随机生成）: "
  read UUID
  if [ -z "$UUID" ]; then
    UUID=$(cat /proc/sys/kernel/random/uuid)
    echo "生成的随机 UUID：$UUID"
  fi

  # 节点密码
  printf "请输入节点密码（留空则随机生成）: "
  read PASSWORD
  if [ -z "$PASSWORD" ]; then
    PASSWORD=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | head -c 20)
    echo "生成的随机密码：$PASSWORD"
  fi

  # 节点显示名称（用于 URL 末尾的 #Name）
  printf "请输入节点名称（用于客户端显示）[默认 TUIC_Node]: "
  read NODE_NAME
  if [ -z "$NODE_NAME" ]; then
    NODE_NAME="TUIC_Node"
  fi

  # SNI / 证书 CN
  printf "请输入伪装域名 SNI（同时用于证书 CN）[默认 bing.com]: "
  read SNI
  if [ -z "$SNI" ]; then
    SNI="bing.com"
  fi

  # 用于 systemd 服务名和目录名的安全名称（只保留字母数字下划线中划线）
  UNIT_NAME=$(echo "$NODE_NAME" | tr ' ' '_' | tr -cd 'A-Za-z0-9_-')
  if [ -z "$UNIT_NAME" ]; then
    UNIT_NAME="tuic_node_${PORT}"
  fi

  NODE_DIR="${TUIC_DIR}/${UNIT_NAME}"
  mkdir -p "$NODE_DIR"

  echo "[*] 为节点 \"$NODE_NAME\" 创建配置目录：$NODE_DIR"

  # 生成自签名证书（CN = SNI）
  echo "[*] 生成自签名证书（CN=${SNI}) ..."
  openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout "${NODE_DIR}/tuic-key.pem" \
    -out "${NODE_DIR}/tuic-cert.pem" \
    -subj "/CN=${SNI}" >/dev/null 2>&1

  # 生成 TUIC v5 服务器配置（JSON）
  echo "[*] 生成 TUIC v5 服务器配置..."
  cat > "${NODE_DIR}/config.json" <<EOF
{
  "server": "[::]:${PORT}",
  "users": {
    "${UUID}": "${PASSWORD}"
  },
  "certificate": "${NODE_DIR}/tuic-cert.pem",
  "private_key": "${NODE_DIR}/tuic-key.pem",
  "congestion_control": "bbr",
  "alpn": ["h3"],
  "udp_relay_ipv6": true,
  "zero_rtt_handshake": false,
  "auth_timeout": "3s",
  "max_idle_time": "10s",
  "max_external_packet_size": 1500,
  "gc_interval": "3s",
  "gc_lifetime": "15s",
  "log_level": "warn"
}
EOF

  # 放行防火墙端口（UDP）
  echo "[*] 配置防火墙，放行 UDP 端口 ${PORT} ..."
  if command -v iptables >/dev/null; then
    iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -p udp --dport "$PORT" -j ACCEPT
  fi
  if command -v ip6tables >/dev/null; then
    ip6tables -C INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null || \
    ip6tables -A INPUT -p udp --dport "$PORT" -j ACCEPT
  fi

  # 保存防火墙配置
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1
  elif command -v service >/dev/null 2>&1; then
    service netfilter-persistent save >/dev/null 2>&1 || true
  fi

  # 创建 systemd 服务单元
  SERVICE_FILE="/etc/systemd/system/tuic-${UNIT_NAME}.service"
  echo "[*] 创建 systemd 服务：tuic-${UNIT_NAME}.service"

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=TUIC v5 service (${NODE_NAME})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/tuic-server -c ${NODE_DIR}/config.json
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  # 重新加载 systemd
  systemctl daemon-reload
  systemctl enable "tuic-${UNIT_NAME}.service" >/dev/null 2>&1

  # 启动服务
  echo "[*] 启动服务 tuic-${UNIT_NAME}.service ..."
  systemctl restart "tuic-${UNIT_NAME}.service"

  sleep 1
  systemctl --no-pager --full status "tuic-${UNIT_NAME}.service" 2>/dev/null | head -n 10

  # 生成 TUIC 节点 URL（适配 v2rayN 等常见格式：
  # tuic://uuid:password@ip:port?alpn=h3&congestion_control=bbr&insecure=1&allowInsecure=1&sni=xxx#Name）
  USERPASS="${UUID}:${PASSWORD}"
  ENCODED_USERPASS=$(printf "%s" "$USERPASS" | sed 's/:/%3A/g')
  ENCODED_NAME=$(printf "%s" "$NODE_NAME" | sed 's/ /%20/g')

  NODE_URL="tuic://${ENCODED_USERPASS}@${PUBLIC_IP}:${PORT}?alpn=h3&congestion_control=bbr&insecure=1&allowInsecure=1&sni=${SNI}#${ENCODED_NAME}"

  echo ""
  echo "==============================================="
  echo "  节点创建完成：$NODE_NAME"
  echo "-----------------------------------------------"
  echo "服务器 IP     : $PUBLIC_IP"
  echo "监听端口       : ${PORT}/udp"
  echo "UUID           : $UUID"
  echo "密码           : $PASSWORD"
  echo "SNI(伪装域名)  : $SNI"
  echo "systemd 服务   : tuic-${UNIT_NAME}.service"
  echo ""
  echo "TUIC 节点链接（V2RayN / Shadowrocket 等可从剪贴板导入）："
  echo "$NODE_URL"
  echo "==============================================="
  echo "在 v2rayN 中：右键节点列表 -> 从剪贴板导入 URL，即可添加此节点。"
  echo ""
}

# 主循环：可连续创建多个节点
while true; do
  printf "是否创建新的 TUIC v5 节点？(y/n) [y]: "
  read ANSWER
  if [ -z "$ANSWER" ]; then
    ANSWER="y"
  fi

  case "$ANSWER" in
    y|Y)
      create_node
      ;;
    n|N)
      echo "已退出，当前已创建的节点可用 systemctl 管理，例如："
      echo "  systemctl restart tuic-<UNIT_NAME>.service"
      echo "  systemctl status tuic-<UNIT_NAME>.service"
      exit 0
      ;;
    *)
      echo "请输入 y 或 n。"
      ;;
  esac
done
