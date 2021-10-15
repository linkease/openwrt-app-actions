

include $(TOPDIR)/rules.mk

PKG_VERSION:=1.0.3
PKG_RELEASE:=20211015

LUCI_TITLE:=LuCI support for jellyfin
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+docker +luci-app-dockerman

define Package/luci-app-jellyfin/conffiles
/etc/config/jellyfin
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

