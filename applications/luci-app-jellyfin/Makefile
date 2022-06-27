

include $(TOPDIR)/rules.mk

PKG_VERSION:=1.1.1
PKG_RELEASE:=20211203

LUCI_TITLE:=LuCI support for jellyfin
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+docker +luci-lib-iform

define Package/luci-app-jellyfin/conffiles
/etc/config/jellyfin
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

