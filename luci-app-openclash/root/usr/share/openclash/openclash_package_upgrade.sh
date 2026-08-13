#!/bin/sh

BACKUP_DIR="${OPENCLASH_UPGRADE_BACKUP_DIR:-/etc/openclash-upgrade-backup}"
STAGING_DIR="${BACKUP_DIR}.new"
PREVIOUS_DIR="${BACKUP_DIR}.previous"
CONFIG_FILE="${OPENCLASH_UPGRADE_CONFIG_FILE:-/etc/config/openclash}"
DATA_DIR="${OPENCLASH_UPGRADE_DATA_DIR:-/etc/openclash}"
LEGACY_DIR="${OPENCLASH_UPGRADE_LEGACY_DIR:-/tmp}"
CORE_EXCLUDE_FILE="${OPENCLASH_UPGRADE_CORE_EXCLUDE_FILE:-/usr/share/openclash/core-backup.exclude}"

log_upgrade() {
	logger -t openclash-upgrade "$*" 2>/dev/null || true
}

backup_upgrade_data() {
	[ -f "$CONFIG_FILE" ] || {
		log_upgrade "OpenClash configuration is missing; refusing to upgrade"
		return 1
	}

	rm -rf "$STAGING_DIR" || return 1
	mkdir -p "$STAGING_DIR" || return 1
	cp -p "$CONFIG_FILE" "$STAGING_DIR/openclash.uci" || return 1

	if [ -d "$DATA_DIR" ]; then
		tar -C "$DATA_DIR" -X "$CORE_EXCLUDE_FILE" -czf "$STAGING_DIR/openclash-data.tar.gz" . || return 1
	else
		tar -czf "$STAGING_DIR/openclash-data.tar.gz" -T /dev/null || return 1
	fi

	if tar -tzf "$STAGING_DIR/openclash-data.tar.gz" | grep -q '^\./core\(/\|$\)'; then
		log_upgrade "Core unexpectedly entered the configuration backup"
		return 1
	fi

	(
		cd "$STAGING_DIR" || exit 1
		sha256sum openclash.uci openclash-data.tar.gz > checksums
	) || return 1

	if [ "${OPENCLASH_UPGRADE_TEST_RUNNING:-0}" = "1" ] || pidof clash >/dev/null 2>&1; then
		echo 1 > "$STAGING_DIR/was-running"
	else
		echo 0 > "$STAGING_DIR/was-running"
	fi
	touch "$STAGING_DIR/backup-complete" || return 1

	rm -rf "$PREVIOUS_DIR" || return 1
	if [ -e "$BACKUP_DIR" ]; then
		mv "$BACKUP_DIR" "$PREVIOUS_DIR" || return 1
	fi
	if ! mv "$STAGING_DIR" "$BACKUP_DIR"; then
		[ -e "$BACKUP_DIR" ] || [ ! -e "$PREVIOUS_DIR" ] || mv "$PREVIOUS_DIR" "$BACKUP_DIR"
		return 1
	fi
	rm -rf "$PREVIOUS_DIR" || return 1
	log_upgrade "Persistent configuration backup completed"
}

restore_persistent_from() {
	restore_dir="$1"
	[ -f "$restore_dir/backup-complete" ] || return 2
	(
		cd "$restore_dir" || exit 1
		sha256sum -c checksums >/dev/null 2>&1
	) || {
		log_upgrade "Persistent configuration backup verification failed: $restore_dir"
		return 1
	}

	if tar -tzf "$restore_dir/openclash-data.tar.gz" | grep -q '^\./core\(/\|$\)'; then
		log_upgrade "Refusing to restore a configuration backup containing a core"
		return 1
	fi

	mkdir -p "$DATA_DIR" || return 1
	cp -p "$restore_dir/openclash.uci" "$CONFIG_FILE" || return 1
	tar -C "$DATA_DIR" -xzf "$restore_dir/openclash-data.tar.gz" || return 1
	cmp -s "$restore_dir/openclash.uci" "$CONFIG_FILE" || return 1
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
	rm -rf "$BACKUP_DIR" "$STAGING_DIR" "$PREVIOUS_DIR" "$LEGACY_DIR/openclash" "$LEGACY_DIR/openclash.bak"
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
