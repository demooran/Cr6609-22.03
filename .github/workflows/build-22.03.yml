#!/usr/bin/env bash
# Safe DIY part 2 for Xiaomi CR6609 / ramips-mt7621 / OpenWrt 22.03
#
# This script intentionally does NOT:
#   - rewrite switch/VLAN ports (the CR6609 port map must be verified first)
#   - force a LAN IP, disable DHCP, or merge WAN into LAN
#   - force regulatory country or transmit power
#   - replace LuCI JavaScript files
#   - disable firewall, dnsmasq, odhcpd, uhttpd, dropbear, or reset buttons
#   - create an open Wi-Fi network
#
# SSID defaults requested by the user: promax / promax_5G.
# Set WIFI_KEY in the GitHub Actions repository Variables (not in a public file),
# or replace the placeholder below with a strong WPA2 passphrase before building.

set -Eeuo pipefail

log() { printf '\n[CR6609 DIY2] %s\n' "$*"; }
die() { printf '[CR6609 DIY2] ERROR: %s\n' "$*" >&2; exit 1; }

TOPDIR="${TOPDIR:-$PWD}"
cd "$TOPDIR"

[[ -f "$TOPDIR/Makefile" && -d "$TOPDIR/package" ]] || \
  die "Run this script from the OpenWrt/ImmortalWrt source root."

# Confirm the intended target before changing the build tree.
if ! grep -q '^CONFIG_TARGET_ramips=y' .config 2>/dev/null ||
   ! grep -q '^CONFIG_TARGET_ramips_mt7621=y' .config 2>/dev/null ||
   ! grep -q '^CONFIG_TARGET_ramips_mt7621_DEVICE_xiaomi_mi-router-cr6609=y' .config 2>/dev/null; then
    die ".config must select ramips/mt7621 and xiaomi_mi-router-cr6609."
fi

# Keep Argon on the v2.3.1 line, appropriate for the older LuCI/opkg-era tree.
# Do not use the modern v3.x source on this 22.03 build.
ARGON_DIR="$TOPDIR/package/luci-theme-argon"
ARGON_URL="https://github.com/jerrykuku/luci-theme-argon.git"
ARGON_TAG="v2.3.1"

if [[ -d "$ARGON_DIR/.git" ]]; then
    log "Updating existing Argon checkout to ${ARGON_TAG}"
    git -C "$ARGON_DIR" fetch --depth 1 origin "refs/tags/${ARGON_TAG}:refs/tags/${ARGON_TAG}"
    git -C "$ARGON_DIR" checkout --detach "$ARGON_TAG"
elif [[ -e "$ARGON_DIR" ]]; then
    die "$ARGON_DIR exists but is not a Git checkout. Remove/rename it in the workflow first."
else
    log "Cloning Argon ${ARGON_TAG}"
    git clone --depth 1 --branch "$ARGON_TAG" "$ARGON_URL" "$ARGON_DIR"
fi

[[ -f "$ARGON_DIR/Makefile" ]] || die "Argon Makefile not found after checkout."

# Ensure the theme is selected in the final build configuration.
if grep -q '^# CONFIG_PACKAGE_luci-theme-argon is not set' .config; then
    sed -i 's/^# CONFIG_PACKAGE_luci-theme-argon is not set/CONFIG_PACKAGE_luci-theme-argon=y/' .config
elif ! grep -q '^CONFIG_PACKAGE_luci-theme-argon=y' .config; then
    printf '\nCONFIG_PACKAGE_luci-theme-argon=y\n' >> .config
fi

# Remove selection of the legacy standalone config app if it was selected.
# Argon v2.3.1 theme and the old separate app are independent; leave the app
# out unless the user explicitly chooses and verifies the matching v0.9 package.
sed -i \
  -e '/^CONFIG_PACKAGE_luci-app-argon-config=y$/d' \
  -e 's/^CONFIG_PACKAGE_luci-app-argon-config=m$/# CONFIG_PACKAGE_luci-app-argon-config is not set/' \
  .config

# Keep LuCI and wireless support selected if they are already provided by the
# device profile; this script does not guess driver/module package names.
log "Argon ${ARGON_TAG} is present and selected."
log "Target selection verified: Xiaomi CR6609 / ramips / mt7621."
log "No radio, VLAN, WAN/LAN, firewall, or reset-button settings were overridden."

# Report the selected packages for the build log.
grep -E '^(CONFIG_PACKAGE_(luci|luci-base|luci-theme-argon|wpad[^=]*))=' .config || true
