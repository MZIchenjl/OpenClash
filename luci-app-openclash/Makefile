include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-openclash
PKG_VERSION:=0.47.156
PKG_RELEASE:=1
PKG_MAINTAINER:=vernesong <https://github.com/vernesong/OpenClash>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)/config
	config PACKAGE_kmod-inet-diag
	default y if PACKAGE_$(PKG_NAME)

	config PACKAGE_luci-compat
	default y if PACKAGE_$(PKG_NAME)

	config PACKAGE_kmod-nft-tproxy
	default y if PACKAGE_firewall4

	config PACKAGE_kmod-ipt-nat
	default y if ! PACKAGE_firewall4

	config PACKAGE_iptables-mod-tproxy
	default y if ! PACKAGE_firewall4

	config PACKAGE_iptables-mod-extra
	default y if ! PACKAGE_firewall4

	config PACKAGE_dnsmasq_full_ipset
	default y if ! PACKAGE_firewall4

	config PACKAGE_dnsmasq_full_nftset
	default y if PACKAGE_firewall4

	config PACKAGE_ipset
	default y if ! PACKAGE_firewall4
endef

define Package/$(PKG_NAME)
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=LuCI support for clash
	PKGARCH:=aarch64_generic
	DEPENDS:=+dnsmasq-full +bash +curl +ca-bundle +ip-full \
	+ruby +ruby-gems +ruby-base64 +ruby-json +ruby-openssl +ruby-uri +ruby-yaml +ruby-zlib \
	+kmod-tun +unzip
	MAINTAINER:=vernesong
endef

define Package/$(PKG_NAME)/description
    OpenClash 0.47.156 bundled with the pinned Mihomo core (x365-v1)
endef

define Build/Prepare
	test -x $(CURDIR)/root/etc/openclash/core/clash_meta
	$(TARGET_CROSS)readelf -h $(CURDIR)/root/etc/openclash/core/clash_meta | grep -q 'Machine:.*AArch64'
	$(CP) $(CURDIR)/root $(PKG_BUILD_DIR)
	$(CP) $(CURDIR)/luasrc $(PKG_BUILD_DIR)
	$(foreach po,$(wildcard ${CURDIR}/po/zh-cn/*.po), \
		po2lmo $(po) $(PKG_BUILD_DIR)/$(patsubst %.po,%.lmo,$(notdir $(po)));)
	chmod 0755 $(PKG_BUILD_DIR)/root/etc/init.d/openclash
	chmod 0755 $(PKG_BUILD_DIR)/root/etc/openclash/core/clash_meta
	chmod 0755 $(PKG_BUILD_DIR)/root/usr/share/openclash/openclash_package_upgrade.sh
	chmod -R 0755 $(PKG_BUILD_DIR)/root/usr/share/openclash/
	exit 0
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/openclash
endef

define Package/$(PKG_NAME)/preinst
#!/bin/sh
	[ "$${PKG_UPGRADE:-0}" = "1" ] || exit 0
	if [ -x "/usr/share/openclash/openclash_package_upgrade.sh" ]; then
		/usr/share/openclash/openclash_package_upgrade.sh backup || exit 1
		exit 0
	fi

	# First upgrade from an upstream package: the helper is not installed yet,
	# so create the same verified persistent backup inline. Any failure aborts
	# the package transaction instead of silently continuing without settings.
	BACKUP_DIR="/etc/openclash-upgrade-backup"
	STAGING_DIR="$${BACKUP_DIR}.new"
	PREVIOUS_DIR="$${BACKUP_DIR}.previous"
	[ -f "/etc/config/openclash" ] || exit 1
	rm -rf "$${STAGING_DIR}" || exit 1
	mkdir -p "$${STAGING_DIR}" || exit 1
	cp -p "/etc/config/openclash" "$${STAGING_DIR}/openclash.uci" || exit 1
	printf '%s\n' './core' './core/*' 'core' 'core/*' > "$${STAGING_DIR}/core.exclude" || exit 1
	if [ -d "/etc/openclash" ]; then
		tar -C "/etc/openclash" -X "$${STAGING_DIR}/core.exclude" -czf "$${STAGING_DIR}/openclash-data.tar.gz" . || exit 1
	else
		tar -czf "$${STAGING_DIR}/openclash-data.tar.gz" -T /dev/null || exit 1
	fi
	if tar -tzf "$${STAGING_DIR}/openclash-data.tar.gz" | grep -q '^\./core\(/\|$$\)'; then
		exit 1
	fi
	(
		cd "$${STAGING_DIR}" || exit 1
		sha256sum openclash.uci openclash-data.tar.gz > checksums
	) || exit 1
	if pidof clash >/dev/null 2>&1; then
		echo 1 > "$${STAGING_DIR}/was-running" || exit 1
	else
		echo 0 > "$${STAGING_DIR}/was-running" || exit 1
	fi
	touch "$${STAGING_DIR}/backup-complete" || exit 1
	rm -rf "$${PREVIOUS_DIR}" || exit 1
	[ ! -e "$${BACKUP_DIR}" ] || mv "$${BACKUP_DIR}" "$${PREVIOUS_DIR}" || exit 1
	if ! mv "$${STAGING_DIR}" "$${BACKUP_DIR}"; then
		[ -e "$${BACKUP_DIR}" ] || [ ! -e "$${PREVIOUS_DIR}" ] || mv "$${PREVIOUS_DIR}" "$${BACKUP_DIR}"
		exit 1
	fi
	rm -rf "$${PREVIOUS_DIR}" || exit 1
	exit 0
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
	exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
	[ -n "$$(pidof clash)" ] && /etc/init.d/openclash stop 2>/dev/null
	exit 0
endef

define Package/$(PKG_NAME)/postrm
#!/bin/sh
	DEFAULT_DNSMASQ_CFGID="$$(uci -q show "dhcp.@dnsmasq[0]" | awk 'NR==1 {split($0, conf, /[.=]/); print conf[2]}' 2>/dev/null)"
	if [ -f "/tmp/etc/dnsmasq.conf.$DEFAULT_DNSMASQ_CFGID" ]; then
	   DNSMASQ_CONF_DIR="$$(awk -F '=' '/^conf-dir=/ {print $2}' "/tmp/etc/dnsmasq.conf.$DEFAULT_DNSMASQ_CFGID" 2>/dev/null)"
	else
	   DNSMASQ_CONF_DIR="/tmp/dnsmasq.d"
	fi
	DNSMASQ_CONF_DIR=$${DNSMASQ_CONF_DIR%*/}
	rm -rf /etc/openclash >/dev/null 2>&1
	rm -rf /etc/config/openclash >/dev/null 2>&1
	rm -rf /tmp/openclash.log >/dev/null 2>&1
	rm -rf /tmp/openclash_start.log >/dev/null 2>&1
	rm -rf /tmp/openclash.change >/dev/null 2>&1
	rm -rf /usr/share/openclash >/dev/null 2>&1
	rm -rf /tmp/openclash_version_history.json >/dev/null 2>&1
    rm -rf /tmp/openclash_cdn_info.json >/dev/null 2>&1
	rm -rf ${DNSMASQ_CONF_DIR}/dnsmasq_openclash_custom_domain.conf >/dev/null 2>&1
	rm -rf ${DNSMASQ_CONF_DIR}/dnsmasq_openclash_chnroute_pass.conf >/dev/null 2>&1
	rm -rf ${DNSMASQ_CONF_DIR}/dnsmasq_openclash_chnroute6_pass.conf >/dev/null 2>&1
	rm -rf /tmp/etc/openclash >/dev/null 2>&1
	rm -rf /tmp/openclash_announcement >/dev/null 2>&1
	rm -rf /www/luci-static/resources/openclash >/dev/null 2>&1
	rm -rf /tmp/oix* >/dev/null 2>&1
	rm -rf /tmp/openclash_oix_version.json >/dev/null 2>&1
	rm -rf /tmp/openclash_version_history_* >/dev/null 2>&1
	rm -rf /tmp/openclash_cdn_info_* >/dev/null 2>&1
	sed -i '/OpenClash Append/,/OpenClash Append End/d' "/usr/lib/lua/luci/model/network.lua" >/dev/null 2>&1
	sed -i '/.*kB maximum content size*/c\HTTP_MAX_CONTENT      = 1024*100		-- 100 kB maximum content size' /usr/lib/lua/luci/http.lua >/dev/null 2>&1
	sed -i '/.*kB maximum content size*/c\export let HTTP_MAX_CONTENT = 1024*100;		// 100 kB maximum content size' /usr/share/ucode/luci/http.uc >/dev/null 2>&1
	uci -q delete firewall.openclash
	uci -q commit firewall
	[ -f "/etc/config/ucitrack" ] && {
	uci -q delete ucitrack.@openclash[-1]
	uci -q commit ucitrack
	}
	rm -rf /tmp/luci-indexcache /tmp/luci-indexcache.* /var/luci-indexcache /var/luci-indexcache.* >/dev/null 2>&1
	rm -rf /tmp/luci-modulecache /var/luci-modulecache >/dev/null 2>&1
	exit 0
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/*.*.lmo $(1)/usr/lib/lua/luci/i18n/
	$(CP) $(PKG_BUILD_DIR)/root/* $(1)/
	$(CP) $(PKG_BUILD_DIR)/luasrc/* $(1)/usr/lib/lua/luci/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
