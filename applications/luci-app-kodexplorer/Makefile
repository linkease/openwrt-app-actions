

include $(TOPDIR)/rules.mk

PKG_VERSION:=1.0.1
PKG_RELEASE:=20211117

LUCI_TITLE:=LuCI support for kodexplorer
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+docker +luci-app-dockerman

define Package/luci-app-kodexplorer/conffiles
/etc/config/kodexplorer
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

