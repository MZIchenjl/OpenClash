# Mihomo submodule workflow

OpenClash pins its customized Mihomo source as the `mihomo` Git submodule. Router-side
OpenClash and core update checks are disabled; releases are built and installed manually.

Clone or initialize the repository with:

```sh
git clone --recurse-submodules https://github.com/MZIchenjl/OpenClash.git
# or, for an existing clone:
git submodule update --init --recursive
```

Advance Mihomo intentionally with:

```sh
git -C mihomo fetch origin feat/x365
git -C mihomo checkout origin/feat/x365
git add mihomo
git commit -m "chore: update pinned mihomo"
```

The `Compile The New Clash Core` workflow is manual-only. It checks out submodules
recursively and compiles the exact Mihomo commit recorded by OpenClash. It no longer
clones `MetaCubeX/mihomo` during the build.

For the NanoPi R5S OpenWrt 25.12.5 build, the package is architecture-specific and owns
the canonical core at `/usr/libexec/openclash/clash_meta`. Package setup atomically copies
it to the OpenClash runtime path `/etc/openclash/core/clash_meta`; this avoids APK's
protected-file handling below `/etc` retaining an older locally installed core. Build it
without installing or starting it:

```sh
docker/openwrt-arm64/package-bundled-apk.sh
```

The build stops unless the checked-out Mihomo source exactly matches the gitlink recorded
by OpenClash. It also rejects dirty Mihomo sources and non-AArch64 binaries.

The human-readable build identifier combines both upstream versions and the local package
revision, for example `0.47.156-alpha-g4e13ff26-x365-v3`. The LuCI home page displays
`0.47.156-x365-v3` for OpenClash and `alpha-g4e13ff26-x365-v3` for Mihomo. APK metadata retains the valid
and upgrade-safe form `0.47.156-r1`. For another x365 packaging revision, increment both
`X365_REVISION` and `PKG_RELEASE`. When OpenClash advances, update `PKG_VERSION`, reset the
release to `1`, and refresh `build-info`.

During an APK upgrade, OpenClash configuration and user data are written to a verified,
persistent backup under `/etc/openclash-upgrade-backup`. The backup never contains
`/etc/openclash/core`; core download, upload, backup, restore, and removal functions are
not exposed because `clash_meta` is owned exclusively by the architecture-specific APK.
After restoration, OpenClash is restarted only when it was running before the upgrade.
Failed restores or restarts retain the persistent backup for recovery.
