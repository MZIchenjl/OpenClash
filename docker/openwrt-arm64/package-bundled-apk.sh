#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
SDK_VOLUME=${OPENWRT_SDK_VOLUME:-openclash-sdk-25-12-5}
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
EXPECTED_OPENCLASH_BUILD_ID="${PACKAGE_VERSION}-x365-${X365_REVISION}"
EXPECTED_MIHOMO_BUILD_ID="alpha-g$(printf '%s' "$PINNED_COMMIT" | cut -c1-8)-x365-${X365_REVISION}"

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
[ "$OPENCLASH_BUILD_ID" = "$EXPECTED_OPENCLASH_BUILD_ID" ] || {
	echo "OPENCLASH_BUILD_ID should be $EXPECTED_OPENCLASH_BUILD_ID" >&2
	exit 1
}
[ "$MIHOMO_BUILD_ID" = "$EXPECTED_MIHOMO_BUILD_ID" ] || {
	echo "MIHOMO_BUILD_ID should be $EXPECTED_MIHOMO_BUILD_ID" >&2
	exit 1
}
[ "$X365_REVISION" = "v$PACKAGE_RELEASE" ] || {
	echo "X365_REVISION must match PKG_RELEASE (expected v$PACKAGE_RELEASE)." >&2
	exit 1
}
docker image inspect "$BUILDER_IMAGE" >/dev/null 2>&1 || {
	docker build --platform linux/amd64 \
		-f "$SCRIPT_DIR/Dockerfile.sdk-builder" \
		-t "$BUILDER_IMAGE" "$SCRIPT_DIR"
}
docker run --rm --platform linux/amd64 \
	-v "$SDK_VOLUME:/sdk:ro" "$BUILDER_IMAGE" sh -ec '
		test -f /sdk/rules.mk
		test -x /sdk/staging_dir/host/bin/apk
		grep -q '\''CONFIG_TARGET_ARCH_PACKAGES="aarch64_generic"'\'' /sdk/.config
	' || {
	echo "OpenWrt 25.12.5 rockchip/armv8 SDK is missing or not configured in Docker volume: $SDK_VOLUME" >&2
	exit 1
}

OUTPUT_DIR=$REPO_ROOT/dist/openclash-arm64-x365-${X365_REVISION}
CORE_OUTPUT=$OUTPUT_DIR/clash_meta
mkdir -p "$OUTPUT_DIR"

BUILD_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
docker run --rm --platform linux/arm64 \
	-v "$REPO_ROOT/mihomo:/src:ro" \
	-v "$OUTPUT_DIR:/output" \
	-v openclash-mihomo-mod:/go/pkg/mod \
	-v openclash-mihomo-build-cache:/root/.cache/go-build \
	-w /src \
	-e "MIHOMO_BUILD_ID=$MIHOMO_BUILD_ID" -e "BUILD_TIME=$BUILD_TIME" \
	golang:1.25-bookworm \
	sh -ec 'CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -mod=readonly \
		-tags with_gvisor -trimpath \
		-ldflags "-X github.com/metacubex/mihomo/constant.Version=$MIHOMO_BUILD_ID -X github.com/metacubex/mihomo/constant.BuildTime=$BUILD_TIME -w -s -buildid=" \
		-o /output/clash_meta .'
chmod 0755 "$CORE_OUTPUT"
file "$CORE_OUTPUT" | grep -q 'ARM aarch64'
strings "$CORE_OUTPUT" | grep -q "$MIHOMO_BUILD_ID"

docker run --rm --platform linux/amd64 \
	-v "$SDK_VOLUME:/sdk" \
	-v "$PACKAGE_SOURCE:/source:ro" \
	-v "$OUTPUT_DIR:/output:ro" \
	-w /sdk "$BUILDER_IMAGE" \
	bash -ec '
		rsync -a --delete --exclude tools/codemirror/node_modules/ /source/ /sdk/package/luci-app-openclash/
		install -D -m 0755 /output/clash_meta /sdk/package/luci-app-openclash/root/usr/libexec/openclash/clash_meta
		install -m 0755 /sdk/package/luci-app-openclash/tools/po2lmo/src/po2lmo /sdk/staging_dir/host/bin/po2lmo
		PATH=/sdk/staging_dir/host/bin:$PATH make -C package/luci-app-openclash clean compile TOPDIR=/sdk V=sc -j1 CONFIG_PACKAGE_luci-app-openclash=y
	'

OUTPUT_APK=$OUTPUT_DIR/luci-app-openclash-${BUILD_ID}-aarch64_generic.apk
docker run --rm --platform linux/amd64 \
	-v "$SDK_VOLUME:/sdk:ro" \
	-v "$OUTPUT_DIR:/output" \
	-e "PACKAGE_VERSION=$PACKAGE_VERSION" -e "PACKAGE_RELEASE=$PACKAGE_RELEASE" \
	-e "OUTPUT_APK=$(basename "$OUTPUT_APK")" \
	"$BUILDER_IMAGE" sh -ec '
		install -m 0644 "/sdk/bin/targets/rockchip/armv8/packages/luci-app-openclash-${PACKAGE_VERSION}-r${PACKAGE_RELEASE}.apk" "/output/$OUTPUT_APK"
	'

docker run --rm --platform linux/amd64 \
	-v "$OUTPUT_DIR:/output:ro" \
	-v "$SDK_VOLUME:/sdk:ro" \
	-w /tmp "$BUILDER_IMAGE" bash -lc "
		set -eu
		APK=/output/$(basename "$OUTPUT_APK")
		APK_TOOL=/sdk/staging_dir/host/bin/apk
		mkdir -p /tmp/package
		\"\$APK_TOOL\" adbdump \"\$APK\" > /tmp/metadata
		grep -q '  name: luci-app-openclash' /tmp/metadata
		grep -q '  version: ${PACKAGE_VERSION}-r${PACKAGE_RELEASE}' /tmp/metadata
		grep -q '  arch: aarch64_generic' /tmp/metadata
		grep -q 'PKG_UPGRADE:-0' /tmp/metadata
		grep -q '/etc/openclash-upgrade-backup' /tmp/metadata
		grep -q '/etc/openclash-upgrade.log' /tmp/metadata
		grep -q 'sha256sum openclash.uci openclash-data.tar.gz' /tmp/metadata
		! grep -q '/tmp/openclash.bak' /tmp/metadata
		\"\$APK_TOOL\" --allow-untrusted extract --destination /tmp/package \"\$APK\" >/dev/null
		file /tmp/package/usr/libexec/openclash/clash_meta | grep -q 'ARM aarch64'
		[ \"\$(stat -c %a /tmp/package/usr/libexec/openclash/clash_meta)\" = 755 ]
		test ! -e /tmp/package/etc/openclash/core/clash_meta
		grep -q 'BUILD_ID=${BUILD_ID}' /tmp/package/usr/share/openclash/build-info
		test -x /tmp/package/usr/share/openclash/openclash_package_upgrade.sh
		test -x /tmp/package/usr/share/openclash/openclash_upgrade_log.sh
		grep -q 'Online OpenClash updates are disabled' /tmp/package/usr/share/openclash/openclash_update.sh
		test ! -e /tmp/package/usr/share/openclash/openclash_core.sh
		grep -q 'core-backup.exclude' /tmp/package/usr/share/openclash/openclash_package_upgrade.sh
		grep -q 'phase=backup result=ok' /tmp/package/usr/share/openclash/openclash_package_upgrade.sh
		test -s /tmp/package/usr/share/openclash/core-backup.exclude
		grep -q 'openclash-package-upgrade-skip-start' /tmp/package/etc/init.d/openclash
		grep -q 'OPENCLASH_BUILD_ID=${OPENCLASH_BUILD_ID}' /tmp/package/usr/share/openclash/build-info
		grep -q 'MIHOMO_BUILD_ID=${MIHOMO_BUILD_ID}' /tmp/package/usr/share/openclash/build-info
		strings /tmp/package/usr/libexec/openclash/clash_meta | grep -q '${MIHOMO_BUILD_ID}'
	"

echo "APK: $OUTPUT_APK"
echo "Package version: ${PACKAGE_VERSION}-r${PACKAGE_RELEASE}"
echo "Build ID: $BUILD_ID"
echo "SHA-256: $(shasum -a 256 "$OUTPUT_APK" | awk '{print $1}')"
