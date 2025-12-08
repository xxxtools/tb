echo "=== 停止并删除 Nezha Agent 服务（OpenRC）==="

# 停止服务
service nezha-agent stop 2>/dev/null || true

# 从开机项移除
rc-update del nezha-agent default 2>/dev/null || true

# 删除 OpenRC 服务脚本
rm -f /etc/init.d/nezha-agent
rm -f /etc/runlevels/default/nezha-agent

echo "=== 删除运行文件、脚本、配置、日志 ==="

# 删除 /run 下的 agent 文件
rm -f /run/nezha-agent /run/nezha-agent.pid
rm -rf /run/nezha-tmp

# 删除你之前的启动脚本
rm -f /usr/local/bin/setup-nezha.sh
rm -f /usr/local/bin/nezha-run-from-run.sh

# 删除你创建的安装脚本
rm -f /root/nezha-alpine-install.sh
rm -f /root/nezha-run-install.sh
rm -f /root/nezha-agent-official-install.sh
rm -f /root/agent.sh

# 删除配置文件
rm -rf /etc/nezha

# 删除日志
rm -f /var/log/nezha-agent.log

echo "=== 若使用官方 install.sh 安装，还需清理官方目录 ==="
rm -rf /opt/nezha 2>/dev/null || true

echo "=== 清理完成，系统已无任何 Nezha Agent 文件 ==="
echo "可以重新安装你要的版本了。"
