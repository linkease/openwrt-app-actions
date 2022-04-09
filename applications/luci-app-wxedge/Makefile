

include $(TOPDIR)/rules.mk

PKG_VERSION:=1.0.1
PKG_RELEASE:=20220409

LUCI_TITLE:=LuCI support for wxedge
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+docker +luci-app-dockerman

define Package/luci-app-wxedge/conffiles
/etc/config/wxedge
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

