#!/bin/sh

echo "=============================="
echo "  哪吒探针 Agent 一键安装 - Alpine"
echo "         交互式版本"
echo "=============================="
echo ""

################################
# 1. 交互输入
################################

# 面板通信地址（域名:端口）
printf "请输入面板通信地址（域名:端口，例如 data.example.com:5555，不要带 http/https）："
read PANEL_ADDR
if [ -z "$PANEL_ADDR" ]; then
    echo "面板通信地址不能为空，退出。"
    exit 1
fi

# Agent 密钥
printf "请输入 Agent 密钥（在面板里看到的 Secret）："
read SECRET
if [ -z "$SECRET" ]; then
    echo "Agent 密钥不能为空，退出。"
    exit 1
fi

# 节点 ID（仅作备注）
printf "请输入节点 ID（可选，不填则随机生成一个数字，作为备注用）："
read NODE_ID
if [ -z "$NODE_ID" ]; then
    NODE_ID="$(date +%s)"
    echo "已自动生成节点 ID：$NODE_ID"
fi

echo ""
echo "========= 配置信息确认 ========="
echo "面板通信地址 : $PANEL_ADDR"
echo "Agent 密钥   : $SECRET"
echo "节点 ID（备注）: $NODE_ID"
echo "================================"
echo ""

################################
# 2. 停止旧服务（如果有）
################################
pkill -f "/run/nezha-agent" 2>/dev/null
service nezha-agent stop 2>/dev/null

################################
# 3. 安装依赖
################################
echo "[*] 安装依赖（wget / ca-certificates / unzip）..."
apk add --no-cache wget ca-certificates unzip

################################
# 4. 创建 setup 脚本（开机执行）
################################
echo "[*] 创建 /usr/local/bin/setup-nezha.sh ..."

cat > /usr/local/bin/setup-nezha.sh <<EOC
#!/bin/sh
mkdir -p /run

PANEL_ADDR="${PANEL_ADDR}"
SECRET="${SECRET}"
NODE_ID="${NODE_ID}"   # 仅作备注，不影响连接逻辑

# 下载 Nezha Agent（linux_amd64）
# 使用官方仓库的最新版本 zip 包
TMP_DIR="/run/nezha-agent-tmp"
rm -rf "\$TMP_DIR"
mkdir -p "\$TMP_DIR"

wget -q -O "\$TMP_DIR/nezha-agent_linux_amd64.zip" \\
  https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_amd64.zip

unzip -q "\$TMP_DIR/nezha-agent_linux_amd64.zip" -d "\$TMP_DIR"

# 一般解压后就是一个叫 nezha-agent 的二进制文件
if [ -f "\$TMP_DIR/nezha-agent" ]; then
    mv "\$TMP_DIR/nezha-agent" /run/nezha-agent
    chmod +x /run/nezha-agent
else
    echo "未在压缩包中找到 nezha-agent 可执行文件，退出。"
    exit 1
fi

# 清理临时文件
rm -rf "\$TMP_DIR"

# 启动 Agent
# 注意：这里的 -s 要写成 “域名:端口”，上面已经由你输入的 PANEL_ADDR 决定
# --tls 表示与面板启用 TLS（如果你的面板是 http 而不是 https，可以去掉 --tls）
/run/nezha-agent -s "\$PANEL_ADDR" -p "\$SECRET" --tls &
echo \$! > /run/nezha-agent.pid
EOC

chmod +x /usr/local/bin/setup-nezha.sh

################################
# 5. 创建 OpenRC 服务文件
################################
echo "[*] 创建 OpenRC 服务：/etc/init.d/nezha-agent ..."

cat > /etc/init.d/nezha-agent <<'EOC'
#!/sbin/openrc-run
name="nezha-agent"
description="Nezha Monitoring Agent (哪吒探针客户端)"
command="/usr/local/bin/setup-nezha.sh"
command_background="yes"
pidfile="/run/nezha-agent.pid"

depend() {
    need net
    after net-online
}

start() {
    ebegin "Starting $name"
    $command
    eend $?
}

stop() {
    ebegin "Stopping $name"
    pkill -f "/run/nezha-agent"
    rm -f $pidfile
    eend $?
}
EOC

chmod +x /etc/init.d/nezha-agent

################################
# 6. 加入开机启动 & 启动服务
################################
rc-update add nezha-agent default

echo "[*] 启动 nezha-agent 服务..."
service nezha-agent start

echo ""
echo "=== 哪吒探针安装完成，服务已启动 ==="
ps aux | grep '[n]ezha-agent' || echo "注意：暂未看到 nezha-agent 进程，请检查。"

echo ""
echo "=========== 最终信息 ==========="
echo "面板通信地址 : $PANEL_ADDR"
echo "Agent 密钥   : $SECRET"
echo "节点 ID（备注）: $NODE_ID"
echo "服务管理     :"
echo "  service nezha-agent restart"
echo "  service nezha-agent status"
echo "================================"
echo ""
