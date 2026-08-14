#!/bin/sh
set -eu

# /etc/openclash 是持久卷。每次启动都用镜像内本次构建的 ARM64 核心更新它，
# 避免重建镜像后仍然误用卷中遗留的旧 Mihomo。
mkdir -p /etc/openclash/core
cp -f /usr/libexec/openclash/clash_meta /etc/openclash/core/clash_meta
chmod 0755 /etc/openclash/core/clash_meta

# 老的命名卷可能建立于这些基础数据加入镜像之前。仅在文件缺失时补齐，
# 已由 OpenClash 在线更新过的数据不会被启动脚本覆盖。
for openclash_data in Country.mmdb GeoSite.dat china_ip_route.ipset china_ip6_route.ipset; do
  if [ ! -s "/etc/openclash/$openclash_data" ]; then
    cp "/usr/libexec/openclash-defaults/$openclash_data" "/etc/openclash/$openclash_data"
    chmod 0644 "/etc/openclash/$openclash_data"
  fi
done

# Docker 测试环境默认使用中文，便于直接验证本分支的 LuCI 翻译；可通过
# OPENCLASH_LUCI_LANGUAGE 覆盖，不影响 OpenClash 在实体路由器上的语言设置。
if [ -n "${OPENCLASH_LUCI_LANGUAGE:-}" ]; then
  uci -q set luci.main.lang="$OPENCLASH_LUCI_LANGUAGE"
  uci -q commit luci
fi

# OpenWrt 不会自动使用 Docker 的 TZ 环境变量；显式设置为宿主测试环境的
# Asia/Shanghai，保证 LuCI 中选择的订阅更新时间就是中国标准时间。
[ -e /etc/config/system ] || touch /etc/config/system
[ -n "$(uci -q get 'system.@system[0]')" ] || uci set system.system=system
uci -q set 'system.@system[0].zonename=Asia/Shanghai'
uci -q set 'system.@system[0].timezone=CST-8'
uci -q commit system

if [ -r /run/secrets/root_password ]; then
  root_password=$(tr -d '\r\n' < /run/secrets/root_password)
  [ -n "$root_password" ] || {
    echo 'Docker root 密码文件为空。' >&2
    exit 1
  }
  printf '%s\n%s\n' "$root_password" "$root_password" | passwd root >/dev/null 2>&1
  unset root_password
fi

# OpenWrt 的设备镜像默认把 eth0 加入 br-lan 并设置 192.168.1.1。
# 在 Docker 中 eth0 由容器网络分配；必须把 Docker 已分配的同一地址和网关
# 交给 netifd，否则它会清空 eth0，导致宿主端口映射失效。
docker_cidr=$(ip -o -4 addr show dev eth0 scope global | awk 'NR == 1 { print $4 }')
docker_gateway=$(ip -4 route show default dev eth0 | awk 'NR == 1 { print $3 }')

[ -n "$docker_cidr" ] && [ -n "$docker_gateway" ] || {
  echo '无法读取 Docker eth0 地址或默认网关。' >&2
  exit 1
}

[ -e /etc/config/network ] || touch /etc/config/network
uci -q delete network.lan || true
while uci -q get 'network.@device[0]' >/dev/null 2>&1; do
  uci -q delete 'network.@device[0]'
done
uci -q delete network.docker || true
uci set network.docker=interface
uci set network.docker.device=eth0
uci set network.docker.proto=static
uci add_list network.docker.ipaddr="$docker_cidr"
uci set network.docker.gateway="$docker_gateway"
uci add_list network.docker.dns=127.0.0.11
uci -q commit network

# 只允许 Docker 暴露出来的宿主端口进入容器；未映射端口仍由 Docker 隔离。
while :; do
  docker_zone=$(uci -q show firewall | sed -n "s/^firewall\.\([^.=]*\)\.name='docker'$/\1/p" | head -n 1)
  [ -n "$docker_zone" ] || break
  uci -q delete "firewall.$docker_zone" || break
done
uci -q delete firewall.docker || true
uci set firewall.docker=zone
uci set firewall.docker.name=docker
uci add_list firewall.docker.network=docker
uci set firewall.docker.input=ACCEPT
uci set firewall.docker.output=ACCEPT
uci set firewall.docker.forward=REJECT
uci -q commit firewall

unset docker_cidr docker_gateway docker_zone openclash_data root_password OPENCLASH_LUCI_LANGUAGE
exec /sbin/init
