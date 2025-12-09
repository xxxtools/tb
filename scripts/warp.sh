curl -O https://raw.githubusercontent.com/bee2024lu/warp/main/menu.sh && \
sed -i "s#WIREGUARD_GO_ENABLE=0#WIREGUARD_GO_ENABLE=1#g" menu.sh && \
bash menu.sh
