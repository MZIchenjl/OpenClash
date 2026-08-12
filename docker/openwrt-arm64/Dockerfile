ARG OPENWRT_BASE_IMAGE=openclash-openwrt:25.12.5-r5s-arm64
FROM ${OPENWRT_BASE_IMAGE}

LABEL org.opencontainers.image.title="OpenClash ARM64 开发测试环境"
LABEL org.opencontainers.image.version="25.12.5"
LABEL org.opencontainers.image.description="OpenWrt 25.12.5 rockchip/armv8 用户空间，用于 OpenClash 与 x365 回归测试"

COPY luci-app-openclash-0.47.156.apk /tmp/luci-app-openclash.apk

RUN mkdir -p /tmp/lock \
 && apk update \
 && apk add \
      bash ca-bundle curl dnsmasq-full ip-full kmod-tun luci luci-base \
      luci-compat ruby ruby-gems ruby-base64 ruby-json ruby-openssl \
      ruby-uri ruby-yaml ruby-zlib unzip \
 && apk add --allow-untrusted --force-overwrite --clean-protected /tmp/luci-app-openclash.apk \
 && test "$(apk info -e luci-app-openclash)" = "luci-app-openclash" \
 && rm /tmp/luci-app-openclash.apk

# 先安装官方 0.47.156 APK，再覆盖当前工作树代码；这样既保留官方静态资源，
# 又确保容器实际测试的是本分支中的 Lua、Ruby、Shell 与 LuCI 页面。
COPY root/ /
COPY luasrc/ /usr/lib/lua/luci/
COPY openclash.zh-cn.lmo /usr/lib/lua/luci/i18n/openclash.zh-cn.lmo
COPY mihomo-linux-arm64 /usr/libexec/mihomo-linux-arm64
COPY root/etc/openclash/Country.mmdb /usr/libexec/openclash-defaults/Country.mmdb
COPY root/etc/openclash/GeoSite.dat /usr/libexec/openclash-defaults/GeoSite.dat
COPY root/etc/openclash/china_ip_route.ipset /usr/libexec/openclash-defaults/china_ip_route.ipset
COPY root/etc/openclash/china_ip6_route.ipset /usr/libexec/openclash-defaults/china_ip6_route.ipset
COPY docker-entrypoint.sh /usr/libexec/openclash-docker-entrypoint
COPY docker-board.json /etc/board.json
COPY container-overrides/02_sysinfo /lib/preinit/02_sysinfo
COPY container-overrides/05_fw_defaults /etc/board.d/05_fw_defaults

RUN mkdir -p /etc/openclash/core \
 && cp /usr/libexec/mihomo-linux-arm64 /etc/openclash/core/clash_meta \
 && chmod 0755 /etc/init.d/openclash /etc/openclash/core/clash_meta /usr/libexec/mihomo-linux-arm64 \
 && chmod 0644 /usr/libexec/openclash-defaults/* \
 && chmod 0755 /usr/libexec/openclash-docker-entrypoint \
 && chmod 0644 /etc/board.json \
 && chmod 0755 /etc/board.d/05_fw_defaults \
 && mkdir -p /etc/crontabs \
 && touch /etc/crontabs/root \
 && chmod 0600 /etc/crontabs/root \
 && chmod -R 0755 /usr/share/openclash \
 && /etc/openclash/core/clash_meta -v \
 && ruby -rbase64 -rjson -ropenssl -ruri -ryaml -rzlib -e 'puts RUBY_VERSION'

ENV INITRAMFS=1
EXPOSE 80 443 7890 7891 9090
STOPSIGNAL SIGTERM
CMD ["/usr/libexec/openclash-docker-entrypoint"]
