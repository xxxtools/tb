#!/bin/sh

echo "=============================="
echo "      TUIC v5 完全卸载工具"
echo "   适配 Ubuntu / Debian / Alpine"
echo "=============================="

# -------------------------------
# 1. 检测系统使用 systemd 还是 openrc
# -------------------------------
if command -v systemctl >/dev/null 2>&1; then
    INIT="systemd"
elif command -v rc-service >/dev/null 2>&1 || command -v openrc >/dev/null 2>&1; then
    INIT="openrc"
else
    INIT="unknown"
fi

echo "检测到初始化系统类型: $INIT"

# -------------------------------
# 2. 停止 TUIC 服务
# -------------------------------
echo "== 停止 TUIC 服务 =="

if [ "$INIT" = "systemd" ]; then
    systemctl stop tuic 2>/dev/null || true
    systemctl disable tuic 2>/dev/null || true
elif [ "$INIT" = "openrc" ]; then
    # Alpine / OpenRC
    if command -v rc-service >/dev/null 2>&1; then
        rc-service tuic stop 2>/dev/null || true
        rc-update del tuic 2>/dev/null || true
    else
        service tuic stop 2>/dev/null || true
    fi
fi

# 杀掉残留进程
pkill -f "/run/tuic-server" 2>/dev/null || true
pkill -f "tuic-server" 2>/dev/null || true

# -------------------------------
# 3. 删除服务文件
# -------------------------------
echo "== 删除服务文件 =="

# systemd 单元
rm -f /etc/systemd/system/tuic.service

# OpenRC 启动脚本（Alpine）
rm -f /etc/init.d/tuic

# -------------------------------
# 4. 删除执行脚本与配置 / 证书 / 二进制
# -------------------------------
echo "== 删除 TUIC 文件 =="

# 通用 setup 脚本
rm -f /usr/local/bin/setup-tuic.sh

# 二进制（我们之前有两种情况：放 /run 或放 /usr/local/bin）
rm -f /run/tuic-server
rm -f /usr/local/bin/tuic-server

# 配置与证书（/run 下的临时版）
rm -f /run/tuic-config.json
rm -f /run/tuic-key.pem
rm -f /run/tuic-cert.pem
rm -f /run/tuic.pid

# 如果你有用到 /etc/tuic 目录（多节点或手动放），可以一起清掉：
# rm -rf /etc/tuic

# -------------------------------
# 5. 尝试从配置中解析端口并删除对应防火墙规则
# -------------------------------
echo "== 清理防火墙规则（尽量只删除 TUIC 端口） =="

PORTS=""

# 主要针对我们前面脚本写入的 /run/tuic-config.json
if [ -f /run/tuic-config.json ]; then
    # 提取 "server": "[::]:PORT" 里的 PORT
    PORTS=$(grep -o '"server"[[:space:]]*:[[:space:]]*"\[::]:[0-9]\+"' /run/tuic-config.json \
      | sed 's/.*\]:\([0-9]\+\)".*/\1/' \
      | sort -u)
fi

if [ -n "$PORTS" ]; then
    echo "找到 TUIC 配置中的端口: $PORTS"
    for P in $PORTS; do
        echo "  - 删除 UDP 端口 $P 的 iptables / ip6tables 规则"
        iptables -D INPUT -p udp --dport "$P" -j ACCEPT 2>/dev/null || true
        ip6tables -D INPUT -p udp --dport "$P" -j ACCEPT 2>/dev/null || true
    done
else
    echo "未能自动从配置中解析端口，跳过 iptables 精确清理。"
    echo "如需手动清除规则，可自行执行类似："
    echo "  iptables -D INPUT -p udp --dport <你的TUIC端口> -j ACCEPT"
    echo "  ip6tables -D INPUT -p udp --dport <你的TUIC端口> -j ACCEPT"
fi

# -------------------------------
# 6. 保存防火墙规则（仅在有持久化工具时）
# -------------------------------
if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save 2>/dev/null || true
elif command -v service >/dev/null 2>&1; then
    service netfilter-persistent save 2>/dev/null || true
fi

# -------------------------------
# 7. 最终提示
# -------------------------------
echo ""
echo "=============================="
echo "      TUIC 已彻底卸载完成"
echo "=============================="
echo "已停止服务、删除启动脚本与二进制、清理 /run 文件。"
echo "如你手工自建过额外配置目录（如 /etc/tuic），请按需自行删除。"
echo ""
