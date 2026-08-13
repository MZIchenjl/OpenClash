#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
SDK_ROOT=${OPENWRT_SDK_ROOT:-$SCRIPT_DIR/.cache/sdk-25.12.5/root}
BUILDER_IMAGE=${OPENCLASH_SDK_BUILDER:-openclash-sdk-builder:bookworm}
BUILD_INFO=$REPO_ROOT/luci-app-openclash/root/usr/share/openclash/build-info
PACKAGE_SOURCE=$REPO_ROOT/luci-app-openclash

[ -f "$BUILD_INFO" ] || {
	echo "Missing build information: $BUILD_INFO" >&2
	exit 1
}

. "$BUILD_INFO"

PACKAGE_VERSION=$(sed -n 's/^PKG_VERSION:=//p' "$PACKAGE_SOURCE/Makefile" | head -n 1)
PACKAGE_RELEASE=$(sed -n 's/^PKG_RELEASE:=//p' "$PACKAGE_SOURCE/Makefile" | head -n 1)
PINNED_COMMIT=$(git -C "$REPO_ROOT" ls-tree HEAD mihomo | awk '{print $3}')
CHECKED_OUT_COMMIT=$(git -C "$REPO_ROOT/mihomo" rev-parse HEAD)
EXPECTED_BUILD_ID="${PACKAGE_VERSION}-alpha-g$(printf '%s' "$PINNED_COMMIT" | cut -c1-8)-x365-${X365_REVISION}"

[ "$PACKAGE_VERSION" = "$OPENCLASH_VERSION" ] || {
	echo "OpenClash version does not match build-info." >&2
	exit 1
}
[ "$PINNED_COMMIT" = "$MIHOMO_COMMIT" ] || {
	echo "The Mihomo gitlink does not match build-info." >&2
	exit 1
}
[ "$CHECKED_OUT_COMMIT" = "$PINNED_COMMIT" ] || {
	echo "The checked-out Mihomo source is not the commit pinned by OpenClash." >&2
	exit 1
}
[ -z "$(git -C "$REPO_ROOT/mihomo" status --porcelain --untracked-files=no)" ] || {
	echo "The pinned Mihomo source has uncommitted changes." >&2
	exit 1
}
[ "$BUILD_ID" = "$EXPECTED_BUILD_ID" ] || {
	echo "BUILD_ID should be $EXPECTED_BUILD_ID" >&2
	exit 1
}
[ "$X365_REVISION" = "v$PACKAGE_RELEASE" ] || {
	echo "X365_REVISION must match PKG_RELEASE (expected v$PACKAGE_RELEASE)." >&2
	exit 1
}
[ -f "$SDK_ROOT/rules.mk" ] && [ -x "$SDK_ROOT/staging_dir/host/bin/apk" ] || {
	echo "OpenWrt 25.12.5 rockchip/armv8 SDK not found: $SDK_ROOT" >&2
	exit 1
}
grep -q 'CONFIG_TARGET_ARCH_PACKAGES="aarch64_generic"' "$SDK_ROOT/.config" || {
	echo "The SDK is not configured for aarch64_generic." >&2
	exit 1
}
docker image inspect "$BUILDER_IMAGE" >/dev/null 2>&1 || {
	echo "SDK builder image not found: $BUILDER_IMAGE" >&2
	exit 1
}

OUTPUT_DIR=$REPO_ROOT/dist/openclash-arm64-x365-${X365_REVISION}
CORE_OUTPUT=$OUTPUT_DIR/clash_meta
SDK_PACKAGE=$SDK_ROOT/package/luci-app-openclash
SDK_CORE=$SDK_PACKAGE/root/etc/openclash/core/clash_meta

mkdir -p "$OUTPUT_DIR" "$SDK_PACKAGE" "$(dirname "$SDK_CORE")"

BUILD_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
(
	cd "$REPO_ROOT/mihomo"
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build \
		-tags with_gvisor \
		-trimpath \
		-ldflags "-X 'github.com/metacubex/mihomo/constant.Version=$BUILD_ID' -X 'github.com/metacubex/mihomo/constant.BuildTime=$BUILD_TIME' -w -s -buildid=" \
		-o "$CORE_OUTPUT" .
)
chmod 0755 "$CORE_OUTPUT"
file "$CORE_OUTPUT" | grep -q 'ARM aarch64'
strings "$CORE_OUTPUT" | grep -q "$BUILD_ID"

rsync -a --delete --exclude tools/codemirror/node_modules/ "$PACKAGE_SOURCE/" "$SDK_PACKAGE/"
mkdir -p "$(dirname "$SDK_CORE")"
install -m 0755 "$CORE_OUTPUT" "$SDK_CORE"

docker run --rm --platform linux/amd64 \
	-v "$SDK_ROOT:/sdk" \
	-w /sdk "$BUILDER_IMAGE" \
	bash -lc 'make -C package/luci-app-openclash clean compile TOPDIR=/sdk V=sc -j1'

SDK_APK=$SDK_ROOT/bin/packages/aarch64_generic/base/luci-app-openclash-${PACKAGE_VERSION}-r${PACKAGE_RELEASE}.apk
OUTPUT_APK=$OUTPUT_DIR/luci-app-openclash-${BUILD_ID}-aarch64_generic.apk
[ -f "$SDK_APK" ] || {
	echo "APK was not produced: $SDK_APK" >&2
	exit 1
}
install -m 0644 "$SDK_APK" "$OUTPUT_APK"

docker run --rm --platform linux/amd64 \
	-v "$OUTPUT_DIR:/output:ro" \
	-v "$SDK_ROOT:/sdk:ro" \
	-w /tmp "$BUILDER_IMAGE" bash -lc "
		set -eu
		APK=/output/$(basename "$OUTPUT_APK")
		APK_TOOL=/sdk/staging_dir/host/bin/apk
		mkdir -p /tmp/package
		\"\$APK_TOOL\" adbdump \"\$APK\" > /tmp/metadata
		grep -q '  name: luci-app-openclash' /tmp/metadata
		grep -q '  version: ${PACKAGE_VERSION}-r${PACKAGE_RELEASE}' /tmp/metadata
		grep -q '  arch: aarch64_generic' /tmp/metadata
		\"\$APK_TOOL\" --allow-untrusted extract --destination /tmp/package \"\$APK\" >/dev/null
		file /tmp/package/etc/openclash/core/clash_meta | grep -q 'ARM aarch64'
		[ \"\$(stat -c %a /tmp/package/etc/openclash/core/clash_meta)\" = 755 ]
		grep -q 'BUILD_ID=${BUILD_ID}' /tmp/package/usr/share/openclash/build-info
		grep -q 'rm -f \"/tmp/openclash/core/clash_meta\"' /tmp/package/etc/uci-defaults/luci-openclash
		strings /tmp/package/etc/openclash/core/clash_meta | grep -q '${BUILD_ID}'
	"

echo "APK: $OUTPUT_APK"
echo "Package version: ${PACKAGE_VERSION}-r${PACKAGE_RELEASE}"
echo "Build ID: $BUILD_ID"
echo "SHA-256: $(shasum -a 256 "$OUTPUT_APK" | awk '{print $1}')"
