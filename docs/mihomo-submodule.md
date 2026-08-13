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

After building, install the OpenClash IPK/APK manually and install the matching core at
`/etc/openclash/core/clash_meta` (or the configured small-flash path).
