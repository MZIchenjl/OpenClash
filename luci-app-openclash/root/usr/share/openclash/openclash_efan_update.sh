#!/bin/sh
. /usr/share/openclash/log.sh
. /usr/share/openclash/openclash_ps.sh
. /usr/share/openclash/uci.sh

LOCK_FILE="/tmp/lock/openclash_efan_update.lock"
restart=0
job_started=0

set_lock() {
   mkdir -p /tmp/lock
   exec 873>"$LOCK_FILE" 2>/dev/null
   flock -n 873 2>/dev/null
}

cleanup() {
   [ "$job_started" -eq 1 ] && dec_job_counter_and_restart "$restart"
   flock -u 873 2>/dev/null
   rm -f "$LOCK_FILE" 2>/dev/null
}

config_checksum() {
   [ -f "$1" ] && md5sum "$1" 2>/dev/null | awk '{print $1}'
}

record_update_state() {
   update_status="$1"
   update_now=$(date +%s)
   uci -q set openclash.config.efan_last_update_attempt="$update_now"
   uci -q set openclash.config.efan_last_update_status="$update_status"
   [ "$update_status" = "success" ] && uci -q set openclash.config.efan_last_update_time="$update_now"
   uci -q commit openclash
}

set_lock || exit 0
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

[ "$(uci_get_config "efan_auto_update" || echo 0)" -eq 1 ] || exit 0

CONFIG_PATH=$(uci_get_config "config_path")
ACTIVE_EFAN=0
case "$CONFIG_PATH" in
   /etc/openclash/config/efan-*.yaml) ACTIVE_EFAN=1 ;;
esac
[ "$ACTIVE_EFAN" -eq 1 ] && BEFORE_CHECKSUM=$(config_checksum "$CONFIG_PATH")

inc_job_counter
job_started=1

RESULT=$(ruby /usr/share/openclash/openclash_efan.rb refresh-all 2>/dev/null)
RUBY_STATUS=$?
RESULT_STATUS=$(jsonfilter -s "$RESULT" -e '@.status' 2>/dev/null)
ACCOUNT_COUNT=$(jsonfilter -s "$RESULT" -e '@.account_count' 2>/dev/null)
READY_COUNT=$(jsonfilter -s "$RESULT" -e '@.ready_count' 2>/dev/null)
FAILED_COUNT=$(jsonfilter -s "$RESULT" -e '@.failed_count' 2>/dev/null)
AUTH_INVALID_COUNT=$(jsonfilter -s "$RESULT" -e '@.auth_invalid_count' 2>/dev/null)

ACCOUNT_COUNT=${ACCOUNT_COUNT:-0}
READY_COUNT=${READY_COUNT:-0}
FAILED_COUNT=${FAILED_COUNT:-0}
AUTH_INVALID_COUNT=${AUTH_INVALID_COUNT:-0}

if [ "$RUBY_STATUS" -ne 0 ] || [ -z "$RESULT_STATUS" ]; then
   record_update_state "failed"
   LOG_WARN "Efan automatic subscription update failed before a valid result was returned."
elif [ "$ACCOUNT_COUNT" -eq 0 ]; then
   record_update_state "no_account"
   LOG_INFO "Efan automatic subscription update skipped: no remembered account."
elif [ "$RESULT_STATUS" = "ok" ]; then
   record_update_state "success"
   LOG_INFO "Efan automatic subscription update completed: ${READY_COUNT} service(s) refreshed across ${ACCOUNT_COUNT} account(s)."
elif [ "$AUTH_INVALID_COUNT" -ne 0 ]; then
   [ "$READY_COUNT" -gt 0 ] && record_update_state "partial" || record_update_state "failed"
   LOG_WARN "Efan automatic subscription update completed with errors: ${READY_COUNT} refreshed, ${FAILED_COUNT} failed, ${AUTH_INVALID_COUNT} token-invalid service(s). Token-invalid account caches were removed; YAML configurations were preserved."
else
   [ "$READY_COUNT" -gt 0 ] && record_update_state "partial" || record_update_state "failed"
   LOG_WARN "Efan automatic subscription update completed with errors: ${READY_COUNT} refreshed and ${FAILED_COUNT} failed. Account caches and last-known-good YAML configurations were preserved."
fi

if [ "$ACTIVE_EFAN" -eq 1 ]; then
   AFTER_CHECKSUM=$(config_checksum "$CONFIG_PATH")
   [ -n "$AFTER_CHECKSUM" ] && [ "$BEFORE_CHECKSUM" != "$AFTER_CHECKSUM" ] && restart=1
fi
