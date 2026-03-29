include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-picoclaw
PKG_VERSION:=1.0.0
PKG_RELEASE:=

LUCI_TITLE:=LuCI support for PicoClaw AI Assistant
LUCI_DESCRIPTION:=PicoClaw is a lightweight AI gateway for OpenWrt routers. This package provides a LuCI web interface for managing PicoClaw service, channels, config, hardware (GPIO/USB), skills, and cron jobs. The PicoClaw binary must be installed separately (see https://github.com/sipeed/picoclaw).
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+luci-lib-jsonc +curl

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
