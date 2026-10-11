# SPDX-License-Identifier: GPL-2.0-only
#

include $(TOPDIR)/rules.mk

PKG_NAME:=qiyougamebooster
PKG_VERSION:=1.2.0
PKG_RELEASE:=1

PKG_SOURCE_SUBDIR:=$(PKG_NAME)_$(PKG_VERSION)
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE_SUBDIR)

PKG_LICENSE:=Proprietary
PKG_MAINTAINER:=qiyougamebooster, Internet1235

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=net
  CATEGORY:=Network
  TITLE:=QiYou Game Boost
  DEPENDS:=+kmod-tun +curl
  URL:=https://www.qiyou.cn
  PKGARCH:=all
endef

define Package/$(PKG_NAME)/description
  Play console games online with less lag and more stability
  — now supporting PS, Switch, Xbox, PC, and mobile.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
	echo "nothing"
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/etc/config

	$(CP) ./files/qiyougamebooster.sh $(1)/usr/bin/qiyougamebooster.sh
	chmod 755 $(1)/usr/bin/qiyougamebooster.sh

	$(CP) ./files/qiyougamebooster.init $(1)/etc/init.d/qiyougamebooster
	chmod 755 $(1)/etc/init.d/qiyougamebooster

	$(CP) ./files/qiyougamebooster.cfg $(1)/etc/config/qiyougamebooster
	chmod 755 $(1)/etc/config/qiyougamebooster
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
