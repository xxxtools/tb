#!/bin/sh

echo "=============================="
echo "  Hysteria2 完全卸载工具"
echo "   适配 Ubuntu / Debian / Alpine"
echo "=============================="

### 检测系统使用 systemd 还是 openrc ###
if command -v systemctl >/dev/null 2>&1; then
    INIT="systemd"
elif command -v rc-service >/dev/null 2>&1; then
    INIT="openrc"
else
    INIT="unknown"
fi

echo "检测到系统初始化方式: $INIT"

### 停止服务 ###
echo "== 停止 Hysteria2 服务 =="

if [ "$INIT" = "systemd" ]; then
    systemctl stop hysteria 2>/dev/null || true
    systemctl disable hysteria 2>/dev/null || true
elif [ "$INIT" = "openrc" ]; then
    rc-service hysteria stop 2>/dev/null || true
    rc-update del hysteria 2>/dev/null || true
fi

pkill -f "/run/hysteria server" 2>/dev/null || true
pkill -f hysteria 2>/dev/null || true

### 删除 systemd 或 OpenRC 服务文件 ###
echo "== 删除服务文件 =="

rm -f /etc/systemd/system/hysteria.service
rm -f /etc/init.d/hysteria

### 删除执行脚本与配置文件 ###
echo "== 删除 Hysteria2 文件 =="

rm -f /usr/local/bin/setup-hysteria.sh
rm -f /run/hysteria
rm -f /run/hysteria-config.yaml
rm -f /run/hysteria-key.pem
rm -f /run/hysteria-cert.pem
rm -f /run/hysteria.pid

### 清理防火墙规则 ###
echo "== 清理防火墙规则 (UDP 40443 及历史端口) =="

for PORT in $(seq 1 65535); do
    iptables -D INPUT -p udp --dport $PORT -j ACCEPT 2>/dev/null
    ip6tables -D INPUT -p udp --dport $PORT -j ACCEPT 2>/dev/null
done

### 保存防火墙规则 ###
if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save 2>/dev/null || true
elif command -v service >/dev/null 2>&1; then
    service netfilter-persistent save 2>/dev/null || true
fi

echo ""
echo "=============================="
echo " Hysteria2 已彻底卸载并清理干净"
echo "=============================="
echo "你现在可以安全地安装 TUIC / 其他协议"
echo ""
