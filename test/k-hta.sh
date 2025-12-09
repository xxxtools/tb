# 1. 停掉服务
rc-service hysteria stop 2>/dev/null || true
rc-service tuic stop 2>/dev/null || true

# 2. 从开机启动中移除
rc-update del hysteria 2>/dev/null || true
rc-update del tuic 2>/dev/null || true

# 3. 删除 OpenRC 启动脚本
rm -f /etc/init.d/hysteria /etc/init.d/tuic

# 4. 删除 setup 脚本和运行时文件
rm -f /usr/local/bin/setup-hysteria.sh /usr/local/bin/setup-tuic.sh
rm -f /run/hysteria /run/hysteria-config.yaml /run/hysteria-*.pem /run/hysteria.pid
rm -f /run/tuic-server /run/tuic-config.json /run/tuic-*.pem /run/tuic.pid
