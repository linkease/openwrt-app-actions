include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-picoclaw
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

LUCI_TITLE:=LuCI support for PicoClaw AI Assistant
LUCI_DESCRIPTION:=PicoClaw is a lightweight AI gateway for OpenWrt routers. This package provides a LuCI web interface for managing PicoClaw service, channels, config, hardware (GPIO/USB), skills, and cron jobs.
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+picoclaw +luci-lib-jsonc +curl +coreutils-nohup

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
