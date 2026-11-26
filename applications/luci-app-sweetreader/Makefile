include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-sweetreader
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

LUCI_TITLE:=LuCI support for SweetReader
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+docker +luci-lib-taskd

define Package/$(PKG_NAME)/conffiles
/etc/config/sweetreader
endef

include $(TOPDIR)/feeds/luci/luci.mk
