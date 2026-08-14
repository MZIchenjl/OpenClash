#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SETTINGS="$ROOT_DIR/luci-app-openclash/luasrc/model/cbi/openclash/settings.lua"
STATUS="$ROOT_DIR/luci-app-openclash/luasrc/view/openclash/status.htm"
CONTROLLER="$ROOT_DIR/luci-app-openclash/luasrc/controller/openclash.lua"
INIT="$ROOT_DIR/luci-app-openclash/root/etc/init.d/openclash"
UCI_DEFAULTS="$ROOT_DIR/luci-app-openclash/root/etc/uci-defaults/luci-openclash"
PLUGIN_UPDATER="$ROOT_DIR/luci-app-openclash/root/usr/share/openclash/openclash_update.sh"
CORE_UPDATER="$ROOT_DIR/luci-app-openclash/root/usr/share/openclash/openclash_core.sh"
CONFIG_MODEL="$ROOT_DIR/luci-app-openclash/luasrc/model/cbi/openclash/config.lua"
UPLOAD_VIEW="$ROOT_DIR/luci-app-openclash/luasrc/view/openclash/upload.htm"
UPDATE_VIEW="$ROOT_DIR/luci-app-openclash/luasrc/view/openclash/update.htm"
SUBMODULES="$ROOT_DIR/.gitmodules"
CORE_WORKFLOW="$ROOT_DIR/.github/workflows/compile_meta_core.yml"
MAKEFILE="$ROOT_DIR/luci-app-openclash/Makefile"
BUILD_INFO="$ROOT_DIR/luci-app-openclash/root/usr/share/openclash/build-info"

if grep -q 'tab("version_update"' "$SETTINGS"; then
  echo "online update tab is still registered" >&2
  exit 1
fi

if grep -q 'last_version' "$STATUS"; then
  echo "status page still checks the latest online version" >&2
  exit 1
fi

for route in last_version opupdate coreupdate core_download one_key_update version_history addr_info check_core remove_all_core backup_only_core backup_ex_core; do
  if grep -q "entry({\"admin\", \"services\", \"openclash\", \"$route\"}" "$CONTROLLER"; then
    echo "online update route is still registered: $route" >&2
    exit 1
  fi
done

if grep -q 'openclash_core.sh "$core_type"' "$INIT"; then
  echo "startup still downloads a missing core" >&2
  exit 1
fi

grep -q 'OPENCLASH_UPGRADE_WAS_RUNNING' "$UCI_DEFAULTS"
grep -q '/etc/init.d/openclash restart' "$UCI_DEFAULTS"
grep -q 'openclash-package-upgrade-skip-start' "$UCI_DEFAULTS"
grep -q 'openclash-package-upgrade-skip-start' "$INIT"
grep -q '/etc/openclash-upgrade-backup' "$MAKEFILE"
grep -q 'backup-complete' "$MAKEFILE"
grep -q 'PKG_UPGRADE:-0' "$MAKEFILE"
grep -q 'root/usr/libexec/openclash/clash_meta' "$MAKEFILE"
grep -q 'OPENCLASH_BUILD_ID=0.47.156-x365-v3' "$BUILD_INFO"
grep -q 'MIHOMO_BUILD_ID=alpha-g4e13ff26-x365-v3' "$BUILD_INFO"
grep -q 'local meta_core_path="/etc/openclash/core/clash_meta"' "$CONTROLLER"
grep -q 'OPENCLASH_BUILD_ID=' "$CONTROLLER"
grep -q 'logger -t openclash-efan' "$CONTROLLER"
grep -q '\[Efan\].*summary' "$CONTROLLER"
grep -q '>> /tmp/openclash.log' "$CONTROLLER"
! grep -q 'openclash-upgrade.log.*\[Efan\]' "$CONTROLLER"
grep -q 'BUNDLED_CORE="/usr/libexec/openclash/clash_meta"' "$UCI_DEFAULTS"
if grep -q 'cp -f "/etc/config/openclash" "/tmp/openclash.bak"' "$MAKEFILE"; then
  echo "package upgrade still relies on a volatile /tmp configuration backup" >&2
  exit 1
fi

grep -q 'Online OpenClash updates are disabled' "$PLUGIN_UPDATER"
[ ! -e "$CORE_UPDATER" ]
[ ! -e "$UPDATE_VIEW" ]
if grep -q 'value="clash_meta"' "$UPLOAD_VIEW" || grep -q 'fp == "clash_meta"' "$CONFIG_MODEL"; then
  echo "manual core upload is still available" >&2
  exit 1
fi
if grep -qE 'openclash_core\.sh|core_download|remove_all_core|backup_only_core|backup_ex_core' "$CONTROLLER" "$STATUS"; then
  echo "core management code is still exposed" >&2
  exit 1
fi
grep -q 'path = mihomo' "$SUBMODULES"
grep -q 'url = https://github.com/MZIchenjl/mihomo.git' "$SUBMODULES"
grep -q 'branch = feat/x365' "$SUBMODULES"
grep -q 'src: mihomo' "$CORE_WORKFLOW"
grep -q 'submodules: recursive' "$CORE_WORKFLOW"

if grep -q 'github.com/MetaCubeX/mihomo.git' "$CORE_WORKFLOW"; then
  echo "core workflow still clones MetaCubeX/mihomo directly" >&2
  exit 1
fi

sh -n "$PLUGIN_UPDATER"
sh -n "$INIT"

echo "manual-update-only checks passed"
