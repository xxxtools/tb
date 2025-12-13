#!/bin/sh

echo "=============================="
echo " Hysteria2 一键安装 - Alpine"
echo " 交互式版（支持 ARM64/x86_64，已修复密码生成问题）"
echo "=============================="

# -------------------------------
# 1. 交互输入
# -------------------------------
# 端口
printf "请输入监听端口 [默认 40443]: "
read PORT
[ -z "$PORT" ] && PORT=40443

# 密码（先读输入，后面再生成随机密码，以免 openssl 未安装）
printf "请输入节点密码（留空将自动生成强随机密码）: "
read USER_PASSWORD

# 节点名称
printf "请输入节点名称 [默认 Hysteria2_Node]: "
read NODE_NAME
[ -z "$NODE_NAME" ] && NODE_NAME="Hysteria2_Node"

# SNI 域名
printf "请输入 SNI 伪装域名 [默认 bing.com]: "
read SNI
[ -z "$SNI" ] && SNI="bing.com"

# -------------------------------
# 2. 自动检测架构
# -------------------------------
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
echo "检测到服务器架构: $ARCH → 将下载 $BINARY"

# -------------------------------
# 3. 停止旧服务
# -------------------------------
pkill -f "/run/hysteria server" 2>/dev/null
service hysteria stop 2>/dev/null

# -------------------------------
# 4. 安装依赖（必须先安装 openssl）
# -------------------------------
apk add --no-cache openssl iproute2 iptables ip6tables net-tools ca-certificates wget curl

# -------------------------------
# 5. 处理密码（现在 openssl 已安装，可以安全生成）
# -------------------------------
if [ -z "$USER_PASSWORD" ]; then
    # 使用 openssl 生成强随机密码
    PASSWORD=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 24)
    echo "已自动生成强随机密码: $PASSWORD"
else
    PASSWORD="$USER_PASSWORD"
    echo "使用您输入的密码"
fi

# 确保密码不为空（Hysteria2 不允许空密码）
if [ -z "$PASSWORD" ]; then
    echo "错误：密码不能为空！请重新运行脚本并输入密码或留空自动生成。"
    exit 1
fi

# -------------------------------
# 6. 创建 setup 脚本（开机执行）
# -------------------------------
cat > /usr/local/bin/setup-hysteria.sh <<EOC
#!/bin/sh
mkdir -p /run

# 下载对应架构的 Hysteria2 二进制
wget -q -O /run/hysteria https://download.hysteria.network/app/latest/$BINARY
chmod +x /run/hysteria

# 创建自签名证书
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \\
  -keyout /run/hysteria-key.pem -out /run/hysteria-cert.pem \\
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

# 开放防火墙端口
if command -v iptables >/dev/null; then
    iptables -C INPUT -p udp --dport ${PORT} -j ACCEPT 2>/dev/null || \\
    iptables -A INPUT -p udp --dport ${PORT} -j ACCEPT
fi
if command -v ip6tables >/dev/null; then
    ip6tables -C INPUT -p udp --dport ${PORT} -j ACCEPT 2>/dev/null || \\
    ip6tables -A INPUT -p udp --dport ${PORT} -j ACCEPT
fi

# 启动 Hysteria2
/run/hysteria server -c /run/hysteria-config.yaml &
pidof hysteria > /run/hysteria.pid 2>/dev/null || \\
pgrep -f "/run/hysteria server" > /run/hysteria.pid 2>/dev/null || true
EOC

chmod +x /usr/local/bin/setup-hysteria.sh

# -------------------------------
# 7. OpenRC 服务文件
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

# 添加到开机启动（避免重复添加）
rc-update show default | grep -q hysteria || rc-update add hysteria default

# -------------------------------
# 8. 保存防火墙规则
# -------------------------------
/etc/init.d/iptables save 2>/dev/null
/etc/init.d/ip6tables save 2>/dev/null

# -------------------------------
# 9. 启动服务
# -------------------------------
service hysteria restart

echo ""
echo "=== Hysteria2 安装完成，服务已启动 ==="
ps aux | grep '[h]ysteria' || true

# -------------------------------
# 10. 输出节点信息
# -------------------------------
PUBLIC_IP=$(
  curl -s http://ipv4.ip.sb || \
  wget -qO- http://ipv4.ip.sb || \
  curl -s http://ifconfig.me || \
  wget -qO- http://ifconfig.me || \
  echo "YOUR.SERVER.IP"
)

ENCODED_NAME=$(printf "%s" "$NODE_NAME" | sed 's/ /%20/g')
NODE_URL="hysteria2://${PASSWORD}@${PUBLIC_IP}:${PORT}?insecure=1&sni=${SNI}#${ENCODED_NAME}"

echo ""
echo "=============================="
echo "     Hysteria2 节点信息（可导入）"
echo "=============================="
echo "服务器 IP : $PUBLIC_IP"
echo "节点名称 : $NODE_NAME"
echo "端口     : $PORT"
echo "密码     : $PASSWORD"
echo "SNI      : $SNI"
echo "架构     : $ARCH ($BINARY)"
echo ""
echo "V2RayN 导入链接（复制整行）："
echo "$NODE_URL"
echo "=============================="
echo ""
echo "支持客户端：v2rayN / NekoBox / Clash Verge / NecoBox / Shadowrocket 等"
echo "操作：右键节点列表 → 从剪贴板导入 URL"
echo ""
echo "修改配置 → 编辑 /usr/local/bin/setup-hysteria.sh"
echo "然后执行：service hysteria restart 生效"
echo "=============================="
