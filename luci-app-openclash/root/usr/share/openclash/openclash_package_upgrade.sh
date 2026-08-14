#!/bin/sh

BACKUP_DIR="${OPENCLASH_UPGRADE_BACKUP_DIR:-/etc/openclash-upgrade-backup}"
STAGING_DIR="${BACKUP_DIR}.new"
PREVIOUS_DIR="${BACKUP_DIR}.previous"
CONFIG_FILE="${OPENCLASH_UPGRADE_CONFIG_FILE:-/etc/config/openclash}"
DATA_DIR="${OPENCLASH_UPGRADE_DATA_DIR:-/etc/openclash}"
LEGACY_DIR="${OPENCLASH_UPGRADE_LEGACY_DIR:-/tmp}"
CORE_EXCLUDE_FILE="${OPENCLASH_UPGRADE_CORE_EXCLUDE_FILE:-/usr/share/openclash/core-backup.exclude}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$SCRIPT_DIR/openclash_upgrade_log.sh"

log_upgrade() {
	openclash_upgrade_log "$*"
}

backup_upgrade_data() {
	[ -f "$CONFIG_FILE" ] || {
		openclash_upgrade_error "phase=backup result=failed stage=config-check exit=1 reason=configuration-missing"
		return 1
	}

	log_upgrade "phase=backup event=start"
	rm -rf "$STAGING_DIR" || { openclash_upgrade_error "phase=backup result=failed stage=staging-cleanup exit=1"; return 1; }
	mkdir -p "$STAGING_DIR" || { openclash_upgrade_error "phase=backup result=failed stage=staging-create exit=1"; return 1; }
	cp -p "$CONFIG_FILE" "$STAGING_DIR/openclash.uci" || { openclash_upgrade_error "phase=backup result=failed stage=config-copy exit=1"; return 1; }

	if [ -d "$DATA_DIR" ]; then
		tar -C "$DATA_DIR" -X "$CORE_EXCLUDE_FILE" -czf "$STAGING_DIR/openclash-data.tar.gz" . || { openclash_upgrade_error "phase=backup result=failed stage=data-archive exit=1"; return 1; }
	else
		tar -czf "$STAGING_DIR/openclash-data.tar.gz" -T /dev/null || { openclash_upgrade_error "phase=backup result=failed stage=empty-archive exit=1"; return 1; }
	fi

	if tar -tzf "$STAGING_DIR/openclash-data.tar.gz" | grep -q '^\./core\(/\|$\)'; then
		openclash_upgrade_error "phase=backup result=failed stage=core-exclusion exit=1 reason=core-in-backup"
		return 1
	fi

	(
		cd "$STAGING_DIR" || exit 1
		sha256sum openclash.uci openclash-data.tar.gz > checksums
	) || { openclash_upgrade_error "phase=backup result=failed stage=checksum-create exit=1"; return 1; }

	if [ "${OPENCLASH_UPGRADE_TEST_RUNNING:-0}" = "1" ] || pidof clash >/dev/null 2>&1; then
		echo 1 > "$STAGING_DIR/was-running"
	else
		echo 0 > "$STAGING_DIR/was-running"
	fi
	touch "$STAGING_DIR/backup-complete" || { openclash_upgrade_error "phase=backup result=failed stage=completion-marker exit=1"; return 1; }

	rm -rf "$PREVIOUS_DIR" || { openclash_upgrade_error "phase=backup result=failed stage=previous-cleanup exit=1"; return 1; }
	if [ -e "$BACKUP_DIR" ]; then
		mv "$BACKUP_DIR" "$PREVIOUS_DIR" || { openclash_upgrade_error "phase=backup result=failed stage=previous-rotate exit=1"; return 1; }
	fi
	if ! mv "$STAGING_DIR" "$BACKUP_DIR"; then
		[ -e "$BACKUP_DIR" ] || [ ! -e "$PREVIOUS_DIR" ] || mv "$PREVIOUS_DIR" "$BACKUP_DIR"
		openclash_upgrade_error "phase=backup result=failed stage=backup-activate exit=1"
		return 1
	fi
	rm -rf "$PREVIOUS_DIR" || { openclash_upgrade_error "phase=backup result=failed stage=previous-finalize exit=1"; return 1; }
	log_upgrade "phase=backup result=ok running=$(cat "$BACKUP_DIR/was-running" 2>/dev/null || echo unknown)"
}

restore_persistent_from() {
	restore_dir="$1"
	[ -f "$restore_dir/backup-complete" ] || return 2
	(
		cd "$restore_dir" || exit 1
		sha256sum -c checksums >/dev/null 2>&1
	) || {
		openclash_upgrade_error "phase=restore result=failed stage=checksum-verify exit=1 source=$(basename "$restore_dir")"
		return 1
	}

	if tar -tzf "$restore_dir/openclash-data.tar.gz" | grep -q '^\./core\(/\|$\)'; then
		openclash_upgrade_error "phase=restore result=failed stage=core-exclusion exit=1 reason=core-in-backup"
		return 1
	fi

	mkdir -p "$DATA_DIR" || { openclash_upgrade_error "phase=restore result=failed stage=data-dir-create exit=1"; return 1; }
	cp -p "$restore_dir/openclash.uci" "$CONFIG_FILE" || { openclash_upgrade_error "phase=restore result=failed stage=config-copy exit=1"; return 1; }
	tar -C "$DATA_DIR" -xzf "$restore_dir/openclash-data.tar.gz" || { openclash_upgrade_error "phase=restore result=failed stage=data-extract exit=1"; return 1; }
	cmp -s "$restore_dir/openclash.uci" "$CONFIG_FILE" || { openclash_upgrade_error "phase=restore result=failed stage=config-verify exit=1"; return 1; }
	log_upgrade "phase=restore result=ok source=$(basename "$restore_dir")"
}

restore_persistent_data() {
	restore_persistent_from "$BACKUP_DIR"
	backup_status=$?
	[ "$backup_status" -eq 0 ] && return 0

	# A power loss between the two directory renames can leave the last complete
	# generation here. Prefer a verified previous generation to losing settings.
	restore_persistent_from "$PREVIOUS_DIR"
	previous_status=$?
	[ "$previous_status" -eq 0 ] && return 0

	[ "$backup_status" -eq 2 ] && [ "$previous_status" -eq 2 ] && return 2
	return 1
}

restore_legacy_data() {
	[ -f "$LEGACY_DIR/openclash.bak" ] || return 2
	cp -p "$LEGACY_DIR/openclash.bak" "$CONFIG_FILE" || return 1
	if [ -d "$LEGACY_DIR/openclash" ]; then
		rm -rf "$LEGACY_DIR/openclash/core"
		mkdir -p "$DATA_DIR" || return 1
		cp -a "$LEGACY_DIR/openclash/." "$DATA_DIR/" || return 1
	fi
}

restore_upgrade_data() {
	restore_persistent_data
	persistent_status=$?
	[ "$persistent_status" -eq 0 ] && return 0
	[ "$persistent_status" -eq 2 ] || return "$persistent_status"
	restore_legacy_data
}

cleanup_upgrade_data() {
	rm -rf "$BACKUP_DIR" "$STAGING_DIR" "$PREVIOUS_DIR" "$LEGACY_DIR/openclash" "$LEGACY_DIR/openclash.bak" || {
		openclash_upgrade_error "phase=cleanup result=failed exit=1"
		return 1
	}
	log_upgrade "phase=cleanup result=ok"
}

case "$1" in
	backup)
		backup_upgrade_data
		;;
	restore)
		restore_upgrade_data
		;;
	cleanup)
		cleanup_upgrade_data
		;;
	*)
		echo "Usage: $0 {backup|restore|cleanup}" >&2
		exit 2
		;;
esac
