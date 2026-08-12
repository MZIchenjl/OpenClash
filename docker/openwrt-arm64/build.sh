#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
CACHE_DIR="$SCRIPT_DIR/.cache"
CONTEXT_DIR="$CACHE_DIR/context"

OPENWRT_VERSION=25.12.5
OPENWRT_TARGET=rockchip/armv8
OPENWRT_IMAGE_NAME=openwrt-25.12.5-rockchip-armv8-friendlyarm_nanopi-r5s-ext4-sysupgrade.img.gz
OPENWRT_URL="https://downloads.openwrt.org/releases/$OPENWRT_VERSION/targets/$OPENWRT_TARGET/$OPENWRT_IMAGE_NAME"
OPENWRT_SHA256=7d02fdc12d1339ce5fece5845c3c45c78f6bb8c92f8318fd993a5198bcfe3f9f

OPENCLASH_VERSION=0.47.156
OPENCLASH_ASSET="luci-app-openclash-$OPENCLASH_VERSION.apk"
OPENCLASH_URL="https://github.com/vernesong/OpenClash/releases/download/v$OPENCLASH_VERSION/$OPENCLASH_ASSET"
OPENCLASH_SHA256=1e4f330fc654e0270ac9cfa762af221335567d9b89388219890e8a7745b914ab

BASE_IMAGE="${OPENWRT_BASE_IMAGE:-openclash-openwrt:25.12.5-r5s-arm64}"
RUNTIME_IMAGE="${OPENCLASH_DOCKER_IMAGE:-openclash-dev:25.12.5-arm64-x365}"
MIHOMO_BIN="${MIHOMO_BIN:-$REPO_ROOT/../mihomo/bin/mihomo-linux-arm64}"

sha256_check() {
  expected="$1"
  file="$2"
  actual=$(shasum -a 256 "$file" | awk '{print $1}')
  [ "$actual" = "$expected" ] || {
    echo "校验失败: $file" >&2
    echo "期望: $expected" >&2
    echo "实际: $actual" >&2
    exit 1
  }
}

download_fixed_asset() {
  url="$1"
  destination="$2"
  expected="$3"
  if [ ! -f "$destination" ]; then
    partial="$destination.partial"
    curl -fL --retry 3 --connect-timeout 15 "$url" -o "$partial"
    mv "$partial" "$destination"
  fi
  sha256_check "$expected" "$destination"
}

command -v docker >/dev/null 2>&1 || {
  echo "未找到 Docker。" >&2
  exit 1
}
command -v cc >/dev/null 2>&1 || {
  echo "未找到 C 编译器，无法生成 LuCI 中文翻译文件。" >&2
  exit 1
}

"$SCRIPT_DIR/prepare-env.sh"

mkdir -p "$CACHE_DIR"
download_fixed_asset "$OPENWRT_URL" "$CACHE_DIR/$OPENWRT_IMAGE_NAME" "$OPENWRT_SHA256"
download_fixed_asset "$OPENCLASH_URL" "$CACHE_DIR/$OPENCLASH_ASSET" "$OPENCLASH_SHA256"

[ -x "$MIHOMO_BIN" ] || {
  echo "未找到 ARM64 Mihomo: $MIHOMO_BIN" >&2
  echo "可通过 MIHOMO_BIN=/绝对路径 指定。" >&2
  exit 1
}
file "$MIHOMO_BIN" | grep -q 'ARM aarch64' || {
  echo "Mihomo 不是 ARM64 ELF: $MIHOMO_BIN" >&2
  exit 1
}

if [ "${FORCE_OPENWRT_BASE_REBUILD:-0}" = 1 ] || ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
  work_dir=$(mktemp -d "${TMPDIR:-/tmp}/openclash-openwrt-rootfs.XXXXXX")
  rootfs_dir="$work_dir/rootfs"
  mkdir -p "$rootfs_dir"

  # OpenWrt sysupgrade 镜像在 gzip 流后附带元数据，gzip 可能以 trailing
  # garbage 返回非零；发布物整体已在上方按官方 SHA-256 校验。
  gzip -dc "$CACHE_DIR/$OPENWRT_IMAGE_NAME" > "$work_dir/r5s.img" 2>/dev/null || true
  [ -s "$work_dir/r5s.img" ] || {
    echo "OpenWrt 镜像解压失败。" >&2
    exit 1
  }

  # 固定发布物的第 2 分区是 ext4 rootfs，MBR 中的单位为 512 字节扇区。
  dd if="$work_dir/r5s.img" of="$work_dir/rootfs.ext4" bs=512 skip=131072 count=212992 2>/dev/null
  docker run --rm --privileged \
    -v "$work_dir:/artifacts" \
    alpine:3.22 \
    sh -c 'apk add --no-cache e2fsprogs-extra >/dev/null && debugfs -R "rdump / /artifacts/rootfs" /artifacts/rootfs.ext4'

  grep -q "DISTRIB_RELEASE='25.12.5'" "$rootfs_dir/etc/openwrt_release"
  grep -q "DISTRIB_TARGET='rockchip/armv8'" "$rootfs_dir/etc/openwrt_release"
  [ "$(cat "$rootfs_dir/etc/apk/arch")" = aarch64_generic ]

  COPYFILE_DISABLE=1 tar --no-xattrs -C "$rootfs_dir" -cf - . \
    | docker import --platform linux/arm64 - "$BASE_IMAGE" >/dev/null
fi

# 构建上下文只包含公开源码和固定二进制，不包含实机快照。
next_context=$(mktemp -d "$CACHE_DIR/context.next.XXXXXX")
mkdir -p "$next_context/root" "$next_context/luasrc"
cp "$CACHE_DIR/$OPENCLASH_ASSET" "$next_context/luci-app-openclash-0.47.156.apk"
cp "$MIHOMO_BIN" "$next_context/mihomo-linux-arm64"
cp "$SCRIPT_DIR/docker-entrypoint.sh" "$next_context/docker-entrypoint.sh"
cp "$SCRIPT_DIR/docker-board.json" "$next_context/docker-board.json"
mkdir -p "$next_context/container-overrides"
cp "$SCRIPT_DIR/container-overrides/02_sysinfo" "$next_context/container-overrides/02_sysinfo"
cp "$SCRIPT_DIR/container-overrides/05_fw_defaults" "$next_context/container-overrides/05_fw_defaults"
cp -R "$REPO_ROOT/luci-app-openclash/root/." "$next_context/root/"
cp -R "$REPO_ROOT/luci-app-openclash/luasrc/." "$next_context/luasrc/"

# 官方 APK 内的翻译不包含当前分支新增的 Efan 文案。使用仓库自带的
# OpenWrt po2lmo 源码生成 LMO，确保测试的是页面最终加载的中文翻译。
PO2LMO_DIR="$REPO_ROOT/luci-app-openclash/tools/po2lmo/src"
cc -O2 -I "$PO2LMO_DIR" -o "$CACHE_DIR/po2lmo" \
  "$PO2LMO_DIR/po2lmo.c" "$PO2LMO_DIR/template_lmo.c"
"$CACHE_DIR/po2lmo" \
  "$REPO_ROOT/luci-app-openclash/po/zh-cn/openclash.zh-cn.po" \
  "$next_context/openclash.zh-cn.lmo"

if [ -d "$CONTEXT_DIR" ]; then
  old_context="$CACHE_DIR/context.previous.$(date +%s)"
  mv "$CONTEXT_DIR" "$old_context"
fi
mv "$next_context" "$CONTEXT_DIR"

docker build \
  --platform linux/arm64 \
  --build-arg "OPENWRT_BASE_IMAGE=$BASE_IMAGE" \
  -f "$SCRIPT_DIR/Dockerfile" \
  -t "$RUNTIME_IMAGE" \
  "$CONTEXT_DIR"

echo "构建完成: $RUNTIME_IMAGE"
docker image inspect "$RUNTIME_IMAGE" --format '架构={{.Architecture}} 大小={{.Size}} ID={{.Id}}'
