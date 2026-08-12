#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SNAPSHOT=${1:-}

[ -n "$SNAPSHOT" ] && [ -f "$SNAPSHOT" ] || {
  echo "用法: $0 /绝对路径/openclash-state.tar.gz" >&2
  exit 1
}

case "$SNAPSHOT" in
  /*) ;;
  *) SNAPSHOT=$(CDPATH= cd -- "$(dirname -- "$SNAPSHOT")" && pwd)/$(basename -- "$SNAPSHOT") ;;
esac

"$SCRIPT_DIR/prepare-env.sh"
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d

tries=0
until docker compose -f "$SCRIPT_DIR/docker-compose.yml" exec -T openwrt ubus call system board >/dev/null 2>&1; do
  tries=$((tries + 1))
  [ "$tries" -lt 60 ] || {
    echo "OpenWrt 容器未就绪。" >&2
    exit 1
  }
  sleep 1
done

# tar 包由只读 SSH 流生成，路径必须限定在 OpenClash 状态范围内。
tar -tzf "$SNAPSHOT" | awk '
  $0 !~ /^etc\/config\/openclash$/ &&
  $0 !~ /^etc\/openclash\/(config|custom|rule_provider|proxy_provider|overwrite)(\/|$)/ {
    print "快照包含范围外路径: " $0 > "/dev/stderr"
    bad=1
  }
  END { exit bad }
'

docker compose -f "$SCRIPT_DIR/docker-compose.yml" exec -T openwrt \
  sh -c 'tar -xzf - -C /' < "$SNAPSHOT"

echo "已导入到 Docker 命名卷；原始快照未修改: $SNAPSHOT"
