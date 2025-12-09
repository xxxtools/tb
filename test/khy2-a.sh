#!/bin/sh

echo "=== 停止服务 ==="
systemctl stop hysteria 2>/dev/null || true
systemctl disable hysteria 2>/dev/null || true

echo "=== 删除 systemd 服务 ==="
rm -f /etc/systemd/system/hysteria.service
systemctl daemon-reload

echo "=== 杀死可能残留的进程 ==="
pkill -f "/run/hysteria server" 2>/dev/null || true
pkill -f hysteria 2>/dev/null || true

echo "=== 删除文件 ==="
rm -f /usr/local/bin/setup-hysteria.sh
rm -f /run/hysteria
rm -f /run/hysteria-config.yaml
rm -f /run/hysteria-key.pem
rm -f /run/hysteria-cert.pem
rm -f /run/hysteria.pid

echo "=== 清理防火墙规则（UDP 40443） ==="
iptables -D INPUT -p udp --dport 40443 -j ACCEPT 2>/dev/null || true
ip6tables -D INPUT -p udp --dport 40443 -j ACCEPT 2>/dev/null || true

# 保存持久化规则
if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save
elif command -v service >/dev/null 2>&1; then
    service netfilter-persistent save 2>/dev/null || true
fi

echo "=== Hy2（Hysteria2）卸载完成 ==="
echo "系统已恢复干净，可以放心安装 TUIC。"
