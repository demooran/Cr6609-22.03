#!/usr/bin/env bash

==========================================

Argon Theme for ImmortalWrt 22.03

Xiaomi CR660X

==========================================

echo "Installing Argon Theme v2.3.1 for OpenWrt 22.03"

Remove old Argon versions

rm -rf package/luci-theme-argon
rm -rf package/luci-app-argon-config
rm -rf feeds/luci/themes/luci-theme-argon

Remove old Argon feed if exists

sed -i '/argon2305/d' feeds.conf.default 2>/dev/null || true

Download fixed Argon version

git clone --depth 1 --branch v2.3.1 
https://github.com/jerrykuku/luci-theme-argon.git 
package/luci-theme-argon

if [ ! -d package/luci-theme-argon ]; then
echo "ERROR: Argon download failed!"
exit 1
fi

echo "Argon v2.3.1 downloaded successfully."
