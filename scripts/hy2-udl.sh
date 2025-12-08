#!/bin/sh

# ==========================
# 0. 基础环境设置
# ==========================
export DEBIAN_FRONTEND=noninteractive

# ==========================
# 1. 停止旧服务（如果存在）
# ==========================
pkill -f "/run/hysteria server" 2>/dev/null
systemctl stop hysteria 2>/dev/null || true

# ==========================
# 2. 安装依赖
# ==========================
apt update
apt install -y \
  wget \
  curl \
  openssl \
  iproute2 \
  iptables \
  ip6tables \
  net-tools \
  iptables-persistent

# ==========================
# 3. 创建 setup 脚本
#    每次启动时负责：
#    - 确保 /run 存在
#    - 下载 Hysteria2 二进制
#    - 生成证书
#    - 生成配置
#    - 开放防火墙端口
#    - 启动 Hysteria2
# ==========================
cat > /usr/local/bin/setup-hysteria.sh <<'EOC'
#!/bin/sh

# 确保 /run 存在
mkdir -p /run

# 下载 Hysteria2 二进制到 /run
wget -q -O /run/hysteria https://download.hysteria.network/app/latest/hysteria-linux-amd64
chmod +x /run/hysteria

# 生成自签名证书（固定 CN=bing.com）
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout /run/hysteria-key.pem -out /run/hysteria-cert.pem \
  -subj "/CN=bing.com"

# 创建配置文件（监听所有 IP）
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

# 开放防火墙端口（规则本身由 iptables-persistent 持久化）
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
# 记录 PID（尽量兼容）
pidof hysteria > /run/hysteria.pid 2>/dev/null || \
pgrep -f "/run/hysteria server" > /run/hysteria.pid 2>/dev/null || true
EOC

chmod +x /usr/local/bin/setup-hysteria.sh

# ==========================
# 4. 创建 systemd 服务单元
# ==========================
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

[Install]
WantedBy=multi-user.target
EOC

# ==========================
# 5. 重新加载 systemd & 开机自启
# ==========================
systemctl daemon-reload
systemctl enable hysteria

# ==========================
# 6. 保存防火墙规则（持久化到磁盘）
# ==========================
if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
else
    if command -v service >/dev/null 2>&1; then
        service netfilter-persistent save 2>/dev/null || true
    fi
fi

# ==========================
# 7. 启动服务
# ==========================
systemctl start hysteria

echo "=== 安装完成，服务已启动（Ubuntu/Debian）==="
systemctl --no-pager --full status hysteria 2>/dev/null || true

# ==========================
# 8. 自动生成 V2RayN/Hysteria2 节点链接
# ==========================

# 获取服务器公网 IP
PUBLIC_IP=$(curl -s ipv4.ip.sb || curl -s ifconfig.me || echo "YOUR_SERVER_IP")

PASSWORD="Wz0FjjnT1Gx9Jqads5Fp3Nbg"
PORT="40443"
SNI="bing.com"
NAME="Hysteria2_Node"

NODE_URL="hysteria2://${PASSWORD}@${PUBLIC_IP}:${PORT}?insecure=1&sni=${SNI}#${NAME}"

echo ""
echo "=============================="
echo "     Hysteria2 节点信息"
echo "=============================="
echo "服务器 IP: $PUBLIC_IP"
echo ""
echo "V2RayN 导入链接（复制整行）："
echo "$NODE_URL"
echo "=============================="
echo ""
echo "在 v2rayN 中：右键节点列表 -> 从剪贴板导入，即可添加此节点。"
