#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SETTINGS="$ROOT_DIR/luci-app-openclash/luasrc/model/cbi/openclash/settings.lua"
STATUS="$ROOT_DIR/luci-app-openclash/luasrc/view/openclash/status.htm"
CONTROLLER="$ROOT_DIR/luci-app-openclash/luasrc/controller/openclash.lua"
INIT="$ROOT_DIR/luci-app-openclash/root/etc/init.d/openclash"
PLUGIN_UPDATER="$ROOT_DIR/luci-app-openclash/root/usr/share/openclash/openclash_update.sh"
CORE_UPDATER="$ROOT_DIR/luci-app-openclash/root/usr/share/openclash/openclash_core.sh"
SUBMODULES="$ROOT_DIR/.gitmodules"
CORE_WORKFLOW="$ROOT_DIR/.github/workflows/compile_meta_core.yml"

if grep -q 'tab("version_update"' "$SETTINGS"; then
  echo "online update tab is still registered" >&2
  exit 1
fi

if grep -q 'last_version' "$STATUS"; then
  echo "status page still checks the latest online version" >&2
  exit 1
fi

for route in last_version opupdate coreupdate core_download one_key_update version_history addr_info; do
  if grep -q "entry({\"admin\", \"services\", \"openclash\", \"$route\"}" "$CONTROLLER"; then
    echo "online update route is still registered: $route" >&2
    exit 1
  fi
done

if grep -q 'openclash_core.sh "$core_type"' "$INIT"; then
  echo "startup still downloads a missing core" >&2
  exit 1
fi

grep -q 'Online OpenClash updates are disabled' "$PLUGIN_UPDATER"
grep -q 'Online core updates are disabled' "$CORE_UPDATER"
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
sh -n "$CORE_UPDATER"
sh -n "$INIT"

echo "manual-update-only checks passed"
