#!/bin/sh

OPENCLASH_UPGRADE_LOG_FILE="${OPENCLASH_UPGRADE_LOG_FILE:-/etc/openclash-upgrade.log}"
OPENCLASH_UPGRADE_LOG_LIMIT="${OPENCLASH_UPGRADE_LOG_LIMIT:-262144}"

openclash_upgrade_log() {
	upgrade_message="$*"
	upgrade_timestamp="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date)"
	upgrade_log_dir="${OPENCLASH_UPGRADE_LOG_FILE%/*}"

	if [ -n "$OPENCLASH_UPGRADE_LOG_FILE" ]; then
		mkdir -p "$upgrade_log_dir" 2>/dev/null || true
		if [ -f "$OPENCLASH_UPGRADE_LOG_FILE" ]; then
			upgrade_log_size="$(wc -c < "$OPENCLASH_UPGRADE_LOG_FILE" 2>/dev/null || echo 0)"
			case "$upgrade_log_size" in
				''|*[!0-9]*) upgrade_log_size=0 ;;
			esac
			if [ "$upgrade_log_size" -ge "$OPENCLASH_UPGRADE_LOG_LIMIT" ]; then
				mv -f "$OPENCLASH_UPGRADE_LOG_FILE" "${OPENCLASH_UPGRADE_LOG_FILE}.1" 2>/dev/null || true
			fi
		fi
		printf '%s %s\n' "$upgrade_timestamp" "$upgrade_message" >> "$OPENCLASH_UPGRADE_LOG_FILE" 2>/dev/null || true
		chmod 0600 "$OPENCLASH_UPGRADE_LOG_FILE" 2>/dev/null || true
	fi

	logger -t openclash-upgrade "$upgrade_message" 2>/dev/null || true
}

openclash_upgrade_error() {
	openclash_upgrade_log "$*"
	printf 'openclash-upgrade: %s\n' "$*" >&2
}
