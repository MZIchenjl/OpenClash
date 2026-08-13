#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
HELPER="${OPENCLASH_PACKAGE_UPGRADE_HELPER:-$ROOT_DIR/luci-app-openclash/root/usr/share/openclash/openclash_package_upgrade.sh}"
CORE_EXCLUDE_FILE="${OPENCLASH_CORE_EXCLUDE_FILE:-$ROOT_DIR/luci-app-openclash/root/usr/share/openclash/core-backup.exclude}"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

CONFIG_FILE="$TEST_ROOT/etc/config/openclash"
DATA_DIR="$TEST_ROOT/etc/openclash"
BACKUP_DIR="$TEST_ROOT/etc/openclash-upgrade-backup"
LEGACY_DIR="$TEST_ROOT/tmp"

mkdir -p "$(dirname "$CONFIG_FILE")" "$DATA_DIR/core" "$DATA_DIR/config" "$DATA_DIR/custom" "$DATA_DIR/history" "$LEGACY_DIR"
printf '%s\n' 'config openclash preserved' > "$CONFIG_FILE"
printf '%s\n' 'historical yaml' > "$DATA_DIR/config/history.yaml"
printf '%s\n' 'custom rule' > "$DATA_DIR/custom/rule.list"
printf '%s\n' 'history state' > "$DATA_DIR/history/state.db"
printf '%s\n' 'old package core' > "$DATA_DIR/core/clash_meta"

run_helper() {
	OPENCLASH_UPGRADE_BACKUP_DIR="$BACKUP_DIR" \
	OPENCLASH_UPGRADE_CONFIG_FILE="$CONFIG_FILE" \
	OPENCLASH_UPGRADE_DATA_DIR="$DATA_DIR" \
	OPENCLASH_UPGRADE_LEGACY_DIR="$LEGACY_DIR" \
	OPENCLASH_UPGRADE_CORE_EXCLUDE_FILE="$CORE_EXCLUDE_FILE" \
	OPENCLASH_UPGRADE_TEST_RUNNING=1 \
		sh "$HELPER" "$1"
}

run_helper backup
[ -f "$BACKUP_DIR/backup-complete" ]
[ "$(cat "$BACKUP_DIR/was-running")" = 1 ]
if tar -tzf "$BACKUP_DIR/openclash-data.tar.gz" | grep -q '^\./core\(/\|$\)'; then
	echo "package upgrade backup contains the core" >&2
	exit 1
fi

printf '%s\n' 'new package default config' > "$CONFIG_FILE"
printf '%s\n' 'new package core' > "$DATA_DIR/core/clash_meta"
printf '%s\n' 'replaced yaml' > "$DATA_DIR/config/history.yaml"
run_helper restore

grep -qx 'config openclash preserved' "$CONFIG_FILE"
grep -qx 'historical yaml' "$DATA_DIR/config/history.yaml"
grep -qx 'custom rule' "$DATA_DIR/custom/rule.list"
grep -qx 'history state' "$DATA_DIR/history/state.db"
grep -qx 'new package core' "$DATA_DIR/core/clash_meta"
[ -f "$BACKUP_DIR/backup-complete" ]

# Simulate a power loss after the prior generation was renamed but before the
# newly staged generation became current.
mv "$BACKUP_DIR" "$BACKUP_DIR.previous"
printf '%s\n' 'interrupted package config' > "$CONFIG_FILE"
run_helper restore
grep -qx 'config openclash preserved' "$CONFIG_FILE"
mv "$BACKUP_DIR.previous" "$BACKUP_DIR"

run_helper backup
printf '%s\n' 'corruption' >> "$BACKUP_DIR/openclash-data.tar.gz"
if run_helper restore; then
	echo "corrupted package upgrade backup was accepted" >&2
	exit 1
fi
[ -f "$BACKUP_DIR/backup-complete" ]

run_helper cleanup
[ ! -e "$BACKUP_DIR" ]

echo "package upgrade configuration checks passed"
