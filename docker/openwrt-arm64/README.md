# OpenClash ARM64 Docker 测试环境

这套环境用于在不修改实机的前提下测试 OpenClash、Efan 登录/配置转换和
x365 Mihomo。基础用户空间来自 OpenWrt 官方 NanoPi R5S 25.12.5 ext4
sysupgrade 镜像，容器原生运行在 ARM64 Docker 上。

与实机一致的部分：

- OpenWrt 25.12.5，目标 `rockchip/armv8`，APK 用户空间为 ARM64；
- OpenClash 0.47.165；
- Ruby 3.4 和 Efan 所需标准库；
- 当前 `~/Projects/OpenClash` 工作树的 LuCI、Ruby、Shell 代码；
- 当前 `~/Projects/mihomo` 构建的 ARM64 x365 内核；
- 完整 `procd/ubus/rpcd/uhttpd/crond` 启动链。

容器使用 Docker Desktop 的 ARM64 LinuxKit 内核，不等同于 NanoPi R5S 的
实体内核。因此 LuCI、配置生成、订阅、Mihomo TCP/UDP、定时任务可以在这里
回归；交换芯片驱动、硬件 offload 和实体 WAN/LAN 转发仍需最后在实机确认。

## 构建和启动

```sh
cd ~/Projects/OpenClash/docker/openwrt-arm64
./build.sh
docker compose up -d
./smoke-test.sh
```

## 打包 NanoPi R5S APK

以下命令使用官方 OpenWrt 25.12.5 `rockchip/armv8` SDK。SDK 必须放在 Docker
命名卷中，避免 macOS 默认文件系统的大小写不敏感问题。宿主机需要 `zstd`。

```sh
cd ~/Projects/OpenClash
mkdir -p docker/openwrt-arm64/.cache/sdk-25.12.5
curl -fL --retry 3 \
  https://downloads.openwrt.org/releases/25.12.5/targets/rockchip/armv8/openwrt-sdk-25.12.5-rockchip-armv8_gcc-14.3.0_musl.Linux-x86_64.tar.zst \
  -o docker/openwrt-arm64/.cache/sdk-25.12.5/openwrt-sdk.tar.zst
printf '%s\n' '59194a023968398af64bfa7d8bc3eac322641f6dc9cdbade28a4d9dd41866eba  docker/openwrt-arm64/.cache/sdk-25.12.5/openwrt-sdk.tar.zst' | shasum -a 256 -c -
docker build --platform linux/amd64 \
  -f docker/openwrt-arm64/Dockerfile.sdk-builder \
  -t openclash-sdk-builder:bookworm docker/openwrt-arm64
docker volume create openclash-sdk-25-12-5
zstd -dc docker/openwrt-arm64/.cache/sdk-25.12.5/openwrt-sdk.tar.zst | \
  docker run --rm --platform linux/amd64 -i \
    -v openclash-sdk-25-12-5:/sdk openclash-sdk-builder:bookworm \
    tar -xf - -C /sdk --strip-components=1
docker run --rm --platform linux/amd64 \
  -v openclash-sdk-25-12-5:/sdk -w /sdk \
  openclash-sdk-builder:bookworm make defconfig
./docker/openwrt-arm64/package-bundled-apk.sh
```

产物位于 `dist/openclash-arm64-x365-v5/`，包含固定提交的 x365 Mihomo。
这套 APK 仅适用于使用 `apk` 包管理器且架构为 `aarch64_generic` 的
OpenWrt 25.12.5 R5S 固件。

脚本首次运行会生成 `.secrets/root_password`，权限为 `0600`，且已被 Git
忽略。LuCI 用户名为 `root`，密码就是该文件的内容。
Docker 环境默认把 LuCI 语言设置为中文，可通过
`OPENCLASH_LUCI_LANGUAGE` 环境变量覆盖。
OpenWrt 系统时区固定为 `Asia/Shanghai`（UTC+8），页面选择的订阅更新时间
按中国标准时间执行。
冒烟测试会使用本地随机密码登录 LuCI，并检查 Efan 标签、自动更新星期/小时、
上次更新时间和操作按钮均已实际渲染为中文；密码不会出现在命令参数或输出中。

本机 LuCI 地址：<http://127.0.0.1:18080/cgi-bin/luci/>；默认也监听所有宿主
接口，所以同一局域网可访问 `http://宿主局域网IP:18080/cgi-bin/luci/`。
宿主端口均可通过
`OPENCLASH_LUCI_HTTP_PORT`、`OPENCLASH_LUCI_HTTPS_PORT`、
`OPENCLASH_MIXED_PORT`、`OPENCLASH_SOCKS_PORT` 和
`OPENCLASH_CONTROLLER_PORT` 环境变量覆盖；控制端口默认使用 `29090`，
避免与本机常见的 `19090` 开发端口冲突。

如果只允许本机访问，可设置 `OPENCLASH_BIND_ADDRESS=127.0.0.1`；默认值为
`0.0.0.0`，供局域网设备测试。

## 导入实机配置快照

导入操作只写 Docker 命名卷，不写实机，也不修改原始 tar 文件：

```sh
./import-snapshot.sh \
  /Users/kirin/Downloads/openclash-openwrt-snapshots/openwrt.mzi.red-20260812-readonly/openclash-state.tar.gz
./smoke-test.sh
```

快照、构建缓存和测试产物已被 `.gitignore` 排除。脚本会拒绝包含
`/etc/config/openclash` 与指定 `/etc/openclash` 子目录以外路径的 tar 包。

## 重置 Docker 测试状态

以下命令会删除本项目的两个 Docker 命名卷，不影响实机和本地快照：

```sh
docker compose down -v
```

这是一项破坏性的 Docker 本地操作，执行前应确认当前目录和 Compose 项目名。
