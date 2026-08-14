#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LUCI_HTTP_PORT=${OPENCLASH_LUCI_HTTP_PORT:-18080}
compose() {
  docker compose -f "$SCRIPT_DIR/docker-compose.yml" "$@"
}

"$SCRIPT_DIR/prepare-env.sh"
compose up -d

tries=0
until [ "$(docker inspect --format '{{.State.Health.Status}}' openclash-openwrt-arm64 2>/dev/null || true)" = healthy ]; do
  tries=$((tries + 1))
  [ "$tries" -lt 90 ] || {
    echo "OpenWrt 容器启动超时。" >&2
    compose logs --tail=200 openwrt >&2
    exit 1
  }
  sleep 1
done

echo '[1/9] OpenWrt ARM64 与发行版'
compose exec -T openwrt sh -c '
  board=$(ubus call system board)
  echo "$board" | jsonfilter -e "@.release.version" | grep -qx 25.12.5
  echo "$board" | jsonfilter -e "@.release.target" | grep -qx rockchip/armv8
  [ "$(apk --print-arch)" = aarch64 ]
  uname -m | grep -qx aarch64
  date +%z | grep -qx +0800
'

echo '[2/9] procd、ubus、rpcd、uhttpd 与 crond'
compose exec -T openwrt sh -c '
  ubus list | grep -qx service
  ubus list | grep -qx session
  ubus list | grep -qx luci
  ubus call service list | jsonfilter -e "@.rpcd.instances.instance1.running" | grep -qx true
  ubus call service list | jsonfilter -e "@.uhttpd.instances.instance1.running" | grep -qx true
  pidof crond >/dev/null
'
http_code=$(curl --max-time 10 -k -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:$LUCI_HTTP_PORT/cgi-bin/luci/")
case "$http_code" in 200|301|302|403) ;; *) echo "LuCI HTTP 状态异常: $http_code" >&2; exit 1;; esac

echo '[3/9] OpenClash 与 Ruby 依赖'
compose exec -T openwrt sh -c '
  apk info -e luci-app-openclash >/dev/null
  apk list --installed luci-app-openclash 2>/dev/null | grep -q "^luci-app-openclash-0.47.156 "
  ruby -rbase64 -rjson -ropenssl -ruri -ryaml -rzlib -e "abort unless RUBY_VERSION.start_with?(\"3.4.\")" 2>/dev/null
  test -x /usr/share/openclash/openclash_efan.rb
  test -x /usr/share/openclash/openclash_get_network.lua
  test -f /usr/lib/lua/luci/view/openclash/efan_login.htm
  test -s /usr/lib/lua/luci/i18n/openclash.zh-cn.lmo
  test "$(uci -q get luci.main.lang)" = zh_cn
  /usr/share/openclash/openclash_efan.rb status "" 2>/dev/null | jsonfilter -e "@.status" | grep -qx ok
'

echo '[4/9] Lua、Shell 与 Ruby 语法'
compose exec -T openwrt sh -c '
  ruby -c /usr/share/openclash/openclash_efan.rb 2>/dev/null | grep -q "Syntax OK"
  sh -n /usr/share/openclash/openclash_efan_update.sh
  sh -n /usr/share/openclash/openclash_watchdog.sh
  sh -n /etc/init.d/openclash
  lua -e "assert(loadfile(\"/usr/lib/lua/luci/controller/openclash.lua\"))"
  lua -e "assert(loadfile(\"/usr/lib/lua/luci/model/cbi/openclash/settings.lua\"))"
'

echo '[5/9] APK 升级配置事务与核心所有权'
docker cp "$SCRIPT_DIR/../../tests/test_package_upgrade.sh" openclash-openwrt-arm64:/usr/libexec/test_package_upgrade.sh
compose exec -T openwrt sh -c '
  set -e
  OPENCLASH_PACKAGE_UPGRADE_HELPER=/usr/share/openclash/openclash_package_upgrade.sh \
  OPENCLASH_CORE_EXCLUDE_FILE=/usr/share/openclash/core-backup.exclude \
    sh /usr/libexec/test_package_upgrade.sh
  test ! -e /usr/share/openclash/openclash_core.sh
  ! grep -q "value=\"clash_meta\"" /usr/lib/lua/luci/view/openclash/upload.htm
  ! grep -qE "core_download|remove_all_core|backup_only_core|backup_ex_core" /usr/lib/lua/luci/controller/openclash.lua
  cmp -s /usr/libexec/openclash/clash_meta /etc/openclash/core/clash_meta
'

echo '[6/9] Mihomo ARM64 与 x365 配置解析'
docker cp "$SCRIPT_DIR/x365-smoke.yaml" openclash-openwrt-arm64:/tmp/x365-smoke.yaml
compose exec -T openwrt sh -c '
  /etc/openclash/core/clash_meta -v | grep -q "linux arm64"
  /etc/openclash/core/clash_meta -d /tmp -t -f /tmp/x365-smoke.yaml
'

echo '[7/9] 当前容器配置校验（若存在）'
compose exec -T openwrt sh -c '
  active=$(uci -q get openclash.config.config_path || true)
  if [ -n "$active" ] && [ -f "$active" ]; then
    /etc/openclash/core/clash_meta -d /etc/openclash -t -f "$active"
  else
    echo "容器尚未导入历史配置，跳过。"
  fi
'

echo '[8/9] LuCI 中文页面实际渲染'
luci_cookie=$(mktemp "$SCRIPT_DIR/.cache/luci-cookie.XXXXXX")
luci_page=$(mktemp "$SCRIPT_DIR/.cache/luci-settings.XXXXXX")
cleanup_luci_test() {
  rm -f "$luci_cookie" "$luci_page"
}
trap cleanup_luci_test EXIT HUP INT TERM
luci_root_password=$(tr -d '\r\n' < "$SCRIPT_DIR/.secrets/root_password")
luci_login_code=$(printf 'luci_username=root&luci_password=%s' "$luci_root_password" | curl \
  --max-time 20 -sS -o /dev/null -w '%{http_code}' \
  -c "$luci_cookie" -b "$luci_cookie" -X POST --data-binary @- \
  "http://127.0.0.1:$LUCI_HTTP_PORT/cgi-bin/luci/")
unset luci_root_password
[ "$luci_login_code" = 302 ]
curl --max-time 60 -sS -o "$luci_page" -c "$luci_cookie" -b "$luci_cookie" \
  "http://127.0.0.1:$LUCI_HTTP_PORT/cgi-bin/luci/admin/services/openclash/settings"
for expected_text in \
  'Efan 账号' '自动更新 Efan 订阅' '更新时间(每周)' '更新时间(每天)' \
  '上次自动更新' '上次成功更新时间：' 'class="efan-table-wrap"' 'border-collapse: collapse' \
  '>登录</button>' '更新全部服务'; do
  grep -Fq "$expected_text" "$luci_page"
done
if grep -Fq 'Efan Account' "$luci_page"; then
  echo 'Efan 页面仍含未翻译的标题。' >&2
  exit 1
fi
version_json=$(curl --max-time 20 -sS -c "$luci_cookie" -b "$luci_cookie" \
  "http://127.0.0.1:$LUCI_HTTP_PORT/cgi-bin/luci/admin/services/openclash/update")
printf '%s' "$version_json" | grep -Fq '0.47.156-x365-v3'
printf '%s' "$version_json" | grep -Fq 'alpha-g4e13ff26-x365-v3'
cleanup_luci_test
trap - EXIT HUP INT TERM

echo '[9/9] 敏感文件未进入 Git 与镜像构建上下文'
if git -C "$SCRIPT_DIR/../.." ls-files | grep -E '(^|/)(efan-[^/]+\.json|openclash-state\.tar\.gz)$' >/dev/null; then
  echo '发现不应提交的账号缓存或实机快照。' >&2
  exit 1
fi
if find "$SCRIPT_DIR/.cache/context" -type f -name 'openclash-state.tar.gz' -print -quit 2>/dev/null | grep -q .; then
  echo 'Docker 构建上下文含实机快照。' >&2
  exit 1
fi

echo "全部 Docker 冒烟测试通过；LuCI: http://127.0.0.1:$LUCI_HTTP_PORT/cgi-bin/luci/"
