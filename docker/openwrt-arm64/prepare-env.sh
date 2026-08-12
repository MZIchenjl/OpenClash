#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SECRET_DIR="$SCRIPT_DIR/.secrets"
PASSWORD_FILE="$SECRET_DIR/root_password"

umask 077
mkdir -p "$SECRET_DIR"

if [ ! -s "$PASSWORD_FILE" ]; then
  next_password="$SECRET_DIR/root_password.next"
  openssl rand -hex 12 > "$next_password"
  mv "$next_password" "$PASSWORD_FILE"
fi

chmod 0700 "$SECRET_DIR"
chmod 0600 "$PASSWORD_FILE"

echo "Docker 测试凭据已就绪: $PASSWORD_FILE"
