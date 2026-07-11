#
# Copyright (C) 2026 jjm2473@gmail.com
#
# This is free software, licensed under the GNU General Public License v3.
#

include $(TOPDIR)/rules.mk

PKG_ARCH_BAIDUSDK:=$(ARCH)

PKG_NAME:=baidusdk
PKG_VERSION:=1.0.2
PKG_RELEASE:=
PKG_SOURCE:=baidudrive-binary-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/linkease/istore-packages/releases/download/prebuilt/
PKG_HASH:=728a7dcf1270462ec75304d24afd1b146e4e21469e35e8de7f01172cb0cd7758
PKG_BUILD_DIR:=$(BUILD_DIR)/baidudrive-binary-$(PKG_VERSION)

PKG_BUILD_PARALLEL:=1
PKG_USE_MIPS16:=0
STRIP:=true
RSTRIP:=:

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=net
	CATEGORY:=Network
	SUBMENU:=Web Servers/Proxies
	TITLE:=Baidu NAS SDK runtime
	DEPENDS:=@(x86_64||aarch64)
	URL:=https://github.com/linkease/istore-packages
endef

define Package/$(PKG_NAME)/description
  Baidu NAS SDK runtime files used by BaiduDrive.
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/opt/baidunas-sdk $(1)/opt/baidunas-glibc
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/nas_sdk/$(PKG_ARCH_BAIDUSDK)/baiduNas $(1)/opt/baidunas-sdk/baiduNas
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/nas_sdk/$(PKG_ARCH_BAIDUSDK)/P2PClient.bin $(1)/opt/baidunas-sdk/P2PClient.bin
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/nas_sdk/$(PKG_ARCH_BAIDUSDK)/libkernel.so $(1)/opt/baidunas-sdk/libkernel.so
	$(CP) $(PKG_BUILD_DIR)/glibc/$(PKG_ARCH_BAIDUSDK)/. $(1)/opt/baidunas-glibc/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
