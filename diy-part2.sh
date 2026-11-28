#!/usr/bin/env bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# ==========================================
# 0. ضمان وجود وتفعيل حزم wpad و EoIP في .config بدون تعارض
# ==========================================
if [ -f .config ]; then
    sed -i '/CONFIG_PACKAGE_wpad-/d' .config
    sed -i '/# CONFIG_PACKAGE_wpad-/d' .config
    cat << 'EOF' >> .config
# CONFIG_PACKAGE_wpad-basic is not set
# CONFIG_PACKAGE_wpad-basic-mbedtls is not set
# CONFIG_PACKAGE_wpad-basic-wolfssl is not set
# CONFIG_PACKAGE_wpad-mini is not set
# CONFIG_PACKAGE_wpad-mini-mbedtls is not set
# CONFIG_PACKAGE_wpad-mini-wolfssl is not set
# CONFIG_PACKAGE_wpad-mesh-mbedtls is not set
# CONFIG_PACKAGE_wpad-mesh-wolfssl is not set
# CONFIG_PACKAGE_wpad-wolfssl is not set
# CONFIG_PACKAGE_wpad-openssl is not set
CONFIG_PACKAGE_wpad-mbedtls=y
EOF

    for EOIP_PKG in eoip luci-app-eoip; do
        if grep -q "CONFIG_PACKAGE_${EOIP_PKG}" .config || find package feeds -maxdepth 4 -name "*${EOIP_PKG}*" 2>/dev/null | grep -q .; then
            sed -i "/CONFIG_PACKAGE_${EOIP_PKG}/d" .config
            sed -i "/# CONFIG_PACKAGE_${EOIP_PKG}/d" .config
            echo "CONFIG_PACKAGE_${EOIP_PKG}=y" >> .config
        fi
    done

    make defconfig >/dev/null 2>&1 || true
    if grep -q "^CONFIG_PACKAGE_wpad-basic-wolfssl=y" .config; then
        sed -i '/CONFIG_PACKAGE_wpad-/d' .config
        sed -i '/# CONFIG_PACKAGE_wpad-/d' .config
        cat << 'EOF' >> .config
# CONFIG_PACKAGE_wpad-basic is not set
# CONFIG_PACKAGE_wpad-basic-mbedtls is not set
# CONFIG_PACKAGE_wpad-basic-wolfssl is not set
# CONFIG_PACKAGE_wpad-mini is not set
# CONFIG_PACKAGE_wpad-mini-mbedtls is not set
# CONFIG_PACKAGE_wpad-mini-wolfssl is not set
# CONFIG_PACKAGE_wpad-mesh-mbedtls is not set
# CONFIG_PACKAGE_wpad-mesh-wolfssl is not set
# CONFIG_PACKAGE_wpad-wolfssl is not set
# CONFIG_PACKAGE_wpad-openssl is not set
CONFIG_PACKAGE_wpad-mbedtls=y
EOF
        make defconfig >/dev/null 2>&1 || true
    fi
    echo "✅ تم ضبط حزم wpad-mbedtls و EoIP في .config."
fi

# ==========================================
# 1. تعيين اسم الجهاز (Hostname)
# ==========================================
sed -i 's/OpenWrt/hosam.AX/g' package/base-files/files/bin/config_generate
sed -i 's/ImmortalWrt/hosam.AX/g' package/base-files/files/bin/config_generate

# ==========================================
# 2. إعدادات الواي فاي الافتراضية (تفعيل الراديو)
# ==========================================
WIFI_FILE="package/kernel/mac80211/files/lib/wifi/mac80211.sh"
if [ -f "$WIFI_FILE" ]; then
    sed -i 's/disabled=1/disabled=0/g' "$WIFI_FILE"
fi

# ==========================================
# 3. إعدادات وضع الـ Access Point والجسر br-lan وتمرير VLAN مثل 110
# ==========================================
mkdir -p package/base-files/files/etc/uci-defaults
cat << 'EOF' > package/base-files/files/etc/uci-defaults/99-set-ap-mode
#!/bin/sh

# 1. حذف واجهات الـ WAN
uci delete network.wan 2>/dev/null || true
uci delete network.wan6 2>/dev/null || true

# 2. تعطيل DHCP على LAN
uci set dhcp.lan.ignore=1
uci set dhcp.lan.dynamicdhcp=0

# 3. تعطيل IPv6
uci set dhcp.lan.ra=disabled
uci set dhcp.lan.dhcpv6=disabled
uci set dhcp.lan.ndp=disabled

# 4. تعيين IP ثابت و DNS (بدون Gateway)
uci set network.lan.proto='static'
uci set network.lan.ipaddr='192.168.1.20'
uci set network.lan.netmask='255.255.255.0'
uci set network.lan.dns='8.8.8.8 1.1.1.1'
uci delete network.lan.gateway 2>/dev/null || true

# 5. عزل العملاء
uci set wireless.default_radio0.isolate=1
uci set wireless.default_radio0.disassoc_low_ack=0
if uci get wireless.default_radio1 >/dev/null 2>&1; then
    uci set wireless.default_radio1.isolate=1
    uci set wireless.default_radio1.disassoc_low_ack=0
fi

# 6. تعيين SSID
uci set wireless.default_radio0.ssid='hossam-WIFI.6@'
uci set wireless.default_radio0.encryption='none'
if uci get wireless.default_radio1 >/dev/null 2>&1; then
    uci set wireless.default_radio1.ssid='hossam-WIFI.6@5G'
    uci set wireless.default_radio1.encryption='none'
fi

# 7. ضبط منافذ الجسر br-lan (lan1, lan2, lan3, wan) وتعطيل IPv6 على الجهاز
for dev in $(uci show network 2>/dev/null | grep "=device" | cut -d . -f2 | cut -d = -f1); do
    if [ "$(uci -q get network.$dev.name)" = "br-lan" ]; then
        uci -q delete network.$dev.ports
        for p in lan1 lan2 lan3 wan; do
            uci add_list network.$dev.ports="$p"
        done
        uci set network.$dev.ipv6='0'
    fi
done

# 8. تفعيل وضع promisc على br-lan و eth0 لضمان عدم إسقاط إطارات VLAN في MT7530 DSA
ip link set dev br-lan promisc on 2>/dev/null || true
ip link set dev eth0 promisc on 2>/dev/null || true

uci commit dhcp
uci commit network
uci commit wireless
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-set-ap-mode

# ضمان بقاء promisc مفعلاً على br-lan و eth0 عند إقلاع الشبكة
if [ -f package/base-files/files/etc/rc.local ]; then
    if ! grep -q "promisc on" package/base-files/files/etc/rc.local; then
        sed -i '/exit 0/i ip link set dev br-lan promisc on 2>/dev/null || true\nip link set dev eth0 promisc on 2>/dev/null || true' package/base-files/files/etc/rc.local
    fi
fi

# ==========================================
# 4. دمج خلفية الثيم وتفعيل Argon
# ==========================================
if [ -f .config ] && ! grep -q "CONFIG_PACKAGE_luci-theme-argon=" .config; then
    echo "CONFIG_PACKAGE_luci-theme-argon=y" >> .config
fi

if [ -f "$GITHUB_WORKSPACE/bg.jpg" ]; then
    BG_UPDATED=0
    for BG_DIR in \
        "package/luci-theme-argon/htdocs/luci-static/argon/background" \
        "feeds/luci/themes/luci-theme-argon/htdocs/luci-static/argon/background" \
        "package/luci-theme-argon/root/www/luci-static/argon/background" \
        "feeds/luci/themes/luci-theme-argon/root/www/luci-static/argon/background"
    do
        if [ -d "$BG_DIR" ]; then
            cp -f "$GITHUB_WORKSPACE/bg.jpg" "$BG_DIR/bg.jpg"
            BG_UPDATED=1
        fi
    done
    if [ "$BG_UPDATED" -eq 0 ]; then
        mkdir -p package/base-files/files/www/luci-static/argon/background/
        cp -f "$GITHUB_WORKSPACE/bg.jpg" package/base-files/files/www/luci-static/argon/background/bg.jpg
    fi
    echo "✅ تم نسخ خلفية الثيم بنجاح."
else
    echo "⚠️ تحذير: لم يتم العثور على ملف bg.jpg."
fi

# جعل الثيم الافتراضي هو Argon حصرياً
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile 2>/dev/null || true
sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/modules/luci-base/Makefile 2>/dev/null || true

cat << 'EOF' > package/base-files/files/etc/uci-defaults/98-argon-theme
#!/bin/sh
if [ -d /www/luci-static/argon ]; then
    uci set luci.main.mediaurlbase='/luci-static/argon'
    uci -q set argon.@global[0].bing_background='0'
    uci -q set argon.@global[0].mode='normal'
    uci commit luci
    uci -q commit argon
    rm -rf /tmp/luci-*
fi
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/98-argon-theme

# ==========================================
# 5. تعديل wireless.js (dBm من 20 إلى 38 + Current power + 160 MHz)
# ==========================================
WIRELESS_JS=$(find feeds/luci package -name "wireless.js" -path "*network*" 2>/dev/null | head -n 1)

if [ -n "$WIRELESS_JS" ] && [ -f "$WIRELESS_JS" ]; then
    echo "تم العثور على wireless.js في: $WIRELESS_JS"
    sed -i 's/\r//g' "$WIRELESS_JS"

    if grep -q "for (var i = 0; i < pwrlist.length; i++)" "$WIRELESS_JS"; then
        sed -i 's|for (var i = 0; i < pwrlist.length; i++)|for (var i = 20; i <= 38; i++) { pwrlist.push({dbm: i, mw: Math.round(Math.pow(10, (i-30)/10) * 1000)}); }; pwrlist = pwrlist.filter((v,i,a)=>a.findIndex(t=>(t.dbm===v.dbm))===i); for (var i = 0; i < pwrlist.length; i++)|g' "$WIRELESS_JS"
        echo "✅ تمت إضافة قيم dBm (من 20 إلى 38) بنجاح."
    fi

    sed -i 's/i<=40/i<=38/g; s/i <= 40/i <= 38/g' "$WIRELESS_JS"

    awk '
    {
        gsub(/this\.powerval=this\.wifiNetwork\?this\.wifiNetwork\.getTXPower\(\):null/, "this.powerval=(this.wifiNetwork?(uci.get(\"wireless\",this.wifiNetwork.getWifiDeviceName(),\"txpower\")||this.wifiNetwork.getTXPower()):null)");
        gsub(/this\.powerval = this\.wifiNetwork \? this\.wifiNetwork\.getTXPower\(\) : null/, "this.powerval = (this.wifiNetwork ? (uci.get(\"wireless\", this.wifiNetwork.getWifiDeviceName(), \"txpower\") || this.wifiNetwork.getTXPower()) : null)");
        gsub(/radioNet\.getTXPower\(\)/, "(uci.get(\"wireless\", radioNet.getWifiDeviceName(), \"txpower\") || \"36\")");
        print
    }
    ' "$WIRELESS_JS" > "$WIRELESS_JS.tmp" && mv "$WIRELESS_JS.tmp" "$WIRELESS_JS"

    sed -i 's/htmodelist\.VHT160/true/g; s/htmodelist\.HE160/true/g' "$WIRELESS_JS"
    echo "✅ تم تعديل wireless.js وتحديث Current power بنجاح."
else
    echo "⚠️ لم يتم العثور على wireless.js."
fi

# ==========================================
# 6. تعطيل الخدمات (97)
# ==========================================
cat << 'EOF' > package/base-files/files/etc/uci-defaults/97-disable-router-services
#!/bin/sh
/etc/init.d/firewall disable 2>/dev/null || true
/etc/init.d/eoip disable 2>/dev/null || true
/etc/init.d/mwan3 disable 2>/dev/null || true
/etc/init.d/odhcpd disable 2>/dev/null || true
/etc/init.d/log disable 2>/dev/null || true
/etc/init.d/dnsmasq disable 2>/dev/null || true
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/97-disable-router-services

# ==========================================
# 7. إزالة تبويبات وصفحات SSH و SSH-Keys و HTTP(S) Access من الواجهة نهائياً
# ==========================================
MENU_SYS_JSON="feeds/luci/modules/luci-mod-system/root/usr/share/luci/menu.d/luci-mod-system.json"
if [ -f "$MENU_SYS_JSON" ]; then
    awk '
    /"admin\/system\/admin\/dropbear":/ || /"admin\/system\/admin\/sshkeys":/ || /"admin\/system\/admin\/uhttpd":/ { skip=1; braces=0 }
    skip {
        for (i=1; i<=length($0); i++) {
            c = substr($0, i, 1)
            if (c == "{") braces++
            else if (c == "}") braces--
        }
        if (braces <= 0 && /}/) skip=0
        next
    }
    { print }
    ' "$MENU_SYS_JSON" > "$MENU_SYS_JSON.tmp" && mv "$MENU_SYS_JSON.tmp" "$MENU_SYS_JSON"

    sed -i ':a;N;$!ba;s/,\s*\n\s*}/\n}/g' "$MENU_SYS_JSON" 2>/dev/null || true
    echo "✅ تم حذف تبويبات SSH و SSH-Keys و HTTP(S) Access من قائمة LuCI بنجاح."
fi

DROPBEAR_JS="feeds/luci/modules/luci-mod-system/htdocs/luci-static/resources/view/system/dropbear.js"
if [ -f "$DROPBEAR_JS" ]; then
    cat << 'EOF' > "$DROPBEAR_JS"
'use strict';
'require view';
'require dom';

return view.extend({
	render: function() {
		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('SSH Access')),
			E('p', {}, _('SSH configuration is managed strictly via terminal.'))
		]);
	},
	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
EOF
fi

SSHKEYS_JS="feeds/luci/modules/luci-mod-system/htdocs/luci-static/resources/view/system/sshkeys.js"
if [ -f "$SSHKEYS_JS" ]; then
    cat << 'EOF' > "$SSHKEYS_JS"
'use strict';
'require view';
'require dom';

return view.extend({
	render: function() {
		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('SSH-Keys')),
			E('p', {}, _('SSH keys configuration is hidden.'))
		]);
	},
	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
EOF
fi

# ==========================================
# 8. تعيين طاقة 36 dBm والدولة (PA)
# ==========================================
cat << 'EOF' > package/base-files/files/etc/uci-defaults/99-fix-wifi-power
#!/bin/sh
uci -q batch << 'EOB'
set wireless.@wifi-device[0].disabled=0
set wireless.@wifi-device[1].disabled=0
set wireless.@wifi-device[0].country='PA'
set wireless.@wifi-device[1].country='PA'
set wireless.@wifi-device[0].txpower=36
set wireless.@wifi-device[1].txpower=36
commit wireless
EOB
wifi reload
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-fix-wifi-power

# ==========================================
# 9. تخصيص معلومات النظام في واجهة Status (System)
# ==========================================
SYS_INCLUDE_JS=$(find feeds/luci -path "*/view/status/include/10_system.js" 2>/dev/null | head -n 1)
if [ -n "$SYS_INCLUDE_JS" ] && [ -f "$SYS_INCLUDE_JS" ]; then
    cat << 'EOF' > "$SYS_INCLUDE_JS"
'use strict';
'require baseclass';
'require fs';
'require rpc';
'require uci';

var callLuciVersion = rpc.declare({
	object: 'luci',
	method: 'getVersion'
});

var callSystemBoard = rpc.declare({
	object: 'system',
	method: 'board'
});

var callSystemInfo = rpc.declare({
	object: 'system',
	method: 'info'
});

return baseclass.extend({
	title: _('System'),

	load: function() {
		return Promise.all([
			L.resolveDefault(callSystemBoard(), {}),
			L.resolveDefault(callSystemInfo(), {}),
			L.resolveDefault(callLuciVersion(), {})
		]);
	},

	render: function(data) {
		var boardinfo   = data[0] || {},
		    systeminfo  = data[1] || {},
		    luciversion = (data[2] && data[2].branch) ? data[2].branch + ' ' + (data[2].revision || '') : '';

		var datestr = null;
		if (systeminfo.localtime) {
			var date = new Date(systeminfo.localtime * 1000);
			datestr = '%04d-%02d-%02d %02d:%02d:%02d'.format(
				date.getUTCFullYear(),
				date.getUTCMonth() + 1,
				date.getUTCDate(),
				date.getUTCHours(),
				date.getUTCMinutes(),
				date.getUTCSeconds()
			);
		}

		var customTag = 'Ahosam-wifi-770528863';

		var fields = [
			_('Hostname'),         boardinfo.hostname,
			_('Model'),            boardinfo.model,
			_('Architecture'),     customTag,
			_('Target Platform'),  customTag,
			_('Firmware Version'), customTag,
			_('Kernel Version'),   customTag,
			_('Local Time'),       datestr,
			_('Uptime'),           systeminfo.uptime ? '%t'.format(systeminfo.uptime) : null,
			_('Load Average'),     Array.isArray(systeminfo.load) ? '%.2f, %.2f, %.2f'.format(
				systeminfo.load[0] / 65535.0,
				systeminfo.load[1] / 65535.0,
				systeminfo.load[2] / 65535.0
			) : null
		];

		var table = E('table', { 'class': 'table' });
		for (var i = 0; i < fields.length; i += 2) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, [fields[i]]),
				E('td', { 'class': 'td left' }, [(fields[i + 1] != null) ? fields[i + 1] : '?'])
			]));
		}

		return table;
	}
});
EOF
    echo "✅ تم تخصيص ملف 10_system.js بنجاح."
fi

# ==========================================
# 10. تبسيط صفحة Backup / Flash Firmware وإبقاء Restore و Flash image فقط
# ==========================================
FLASH_JS=$(find feeds/luci -path "*/view/system/flash.js" 2>/dev/null | head -n 1)
if [ -n "$FLASH_JS" ] && [ -f "$FLASH_JS" ]; then
    cat << 'EOF' > "$FLASH_JS"
'use strict';
'require view';
'require dom';
'require fs';
'require rpc';
'require ui';
'require form';
'require baseclass';

var callSystemValidateFirmwareImage = rpc.declare({
	object: 'system',
	method: 'validate_firmware_image',
	params: [ 'path' ]
});

function findStorageSize(procmtd, procpart) {
	var kernsize = 0, rootfsprovsize = 0, efsprovsize = 0, efsvalidsize = 0, rubifs = 0, mtdblocks = {};
	procmtd.split(/\n/).forEach(function(ln) {
		var match = ln.match(/^mtd(\d+): [0-9a-fA-F]+ [0-9a-fA-F]+ "(.+?)"$/);
		if (match) mtdblocks[match[2]] = parseInt(match[1], 10);
	});
	if (mtdblocks.hasOwnProperty('kernel') && mtdblocks.hasOwnProperty('rootfs')) {
		kernsize = parseInt('0x' + (procmtd.match(new RegExp('^mtd' + mtdblocks['kernel'] + ': ([0-9a-fA-F]+)', 'm')) || [0,0])[1], 16);
		rootfsprovsize = parseInt('0x' + (procmtd.match(new RegExp('^mtd' + mtdblocks['rootfs'] + ': ([0-9a-fA-F]+)', 'm')) || [0,0])[1], 16);
	}
	if (mtdblocks.hasOwnProperty('ubi')) {
		rubifs = parseInt('0x' + (procmtd.match(new RegExp('^mtd' + mtdblocks['ubi'] + ': ([0-9a-fA-F]+)', 'm')) || [0,0])[1], 16);
	}
	if (mtdblocks.hasOwnProperty('efs')) {
		efsprovsize = parseInt('0x' + (procmtd.match(new RegExp('^mtd' + mtdblocks['efs'] + ': ([0-9a-fA-F]+)', 'm')) || [0,0])[1], 16);
	}
	if (kernsize > 0 && rootfsprovsize > 0) return kernsize + rootfsprovsize;
	if (rubifs > 0) return rubifs;
	if (efsprovsize > 0 && efsvalidsize > 0) return efsprovsize;
	return 0;
}

var mapdata = { actions: {}, config: {} };
var isReadonlyView = false;

return view.extend({
	load: function() {
		var tasks = [
			L.resolveDefault(fs.stat('/lib/upgrade/platform.sh'), {}),
			fs.trimmed('/proc/sys/kernel/hostname'),
			fs.trimmed('/proc/mtd'),
			fs.trimmed('/proc/partitions'),
			fs.trimmed('/proc/mounts')
		];
		return Promise.all(tasks);
	},

	handleFirstboot: function(ev) {
		if (!confirm(_('Do you really want to erase all settings?')))
			return;

		ui.showModal(_('Erasing...'), [
			E('p', { 'class': 'spinning' }, _('The system is erasing the configuration partition now and will reboot itself when finished.'))
		]);

		fs.exec('/sbin/firstboot', [ '-r', '-y' ]);
		ui.awaitReconnect('192.168.1.20', '192.168.1.1', 'openwrt.lan');
	},

	handleSysupgrade: function(storage_size, has_rootfs_data, ev) {
		return ui.uploadFile('/tmp/firmware.bin', ev.target.firstChild).then(L.bind(function(btn, reply) {
			btn.firstChild.data = _('Checking image…');
			ui.showModal(_('Checking image…'), [
				E('span', { 'class': 'spinning' }, _('Verifying the uploaded image file.'))
			]);
			return callSystemValidateFirmwareImage('/tmp/firmware.bin').then(function(res) {
				return [ reply, res ];
			});
		}, this, ev.target)).then(L.bind(function(btn, reply) {
			return fs.exec('/sbin/sysupgrade', [ '--test', '/tmp/firmware.bin' ]).then(function(res) {
				reply.push(res);
				return reply;
			});
		}, this, ev.target)).then(L.bind(function(btn, res) {
			var opts = {
				keep: [ E('input', { type: 'checkbox' }), false, '-n' ],
				force: [ E('input', { type: 'checkbox' }), true, '--force' ],
				skip_orig: [ E('input', { type: 'checkbox' }), true, '-u' ],
				backup_pkgs: [ E('input', { type: 'checkbox' }), true, '-k' ]
			},
			is_valid = res[1].valid,
			is_forceable = res[1].forceable,
			allow_backup = res[1].allow_backup,
			is_too_big = (storage_size > 0 && res[0].size > storage_size),
			body = [];

			body.push(E('p', _("The flash image was uploaded. Below is the checksum and file size listed, compare them with the original file to ensure data integrity. <br /> Click 'Continue' below to start the flash procedure.")));
			body.push(E('ul', {}, [
				res[0].size ? E('li', {}, '%s: %1024.2mB'.format(_('Size'), res[0].size)) : '',
				res[0].checksum ? E('li', {}, '%s: %s'.format(_('MD5'), res[0].checksum)) : '',
				res[0].sha256sum ? E('li', {}, '%s: %s'.format(_('SHA256'), res[0].sha256sum)) : ''
			]));
			body.push(E('p', {}, E('label', { 'class': 'btn' }, [
				opts.keep[0], ' ', _('Keep settings and retain the current configuration')
			])));

			if (!is_valid || is_too_big) {
				body.push(E('p', { 'class': 'alert-message' }, [
					res[2].stderr ? res[2].stderr : '',
					res[2].stderr ? E('br') : '',
					_('The uploaded image file does not contain a supported format. Make sure that you choose the generic image format for your platform.')
				]));
			}

			if (!allow_backup) {
				body.push(E('p', { 'class': 'alert-message' }, [
					_('The uploaded firmware does not allow keeping current configuration.')
				]));
				opts.keep[0].disabled = true;
			} else {
				opts.keep[0].checked = true;
				if (has_rootfs_data) {
					body.push(E('p', {}, E('label', { 'class': 'btn' }, [
						opts.skip_orig[0], ' ', _('Skip from backup files that are equal to those in /rom')
					])));
				}
			}

			ui.showModal(_('Flash image?'), body.concat([
				E('div', { 'class': 'right' }, [
					E('button', {
						'class': 'btn',
						'click': ui.createHandlerFn(this, function(ev) {
							return fs.remove('/tmp/firmware.bin').finally(ui.hideModal);
						})
					}, [ _('Cancel') ]),
					' ',
					E('button', {
						'class': 'btn cbi-button-action important',
						'click': ui.createHandlerFn(this, function(ev) {
							var args = [ '/tmp/firmware.bin' ];
							if (!opts.keep[0].checked) args.unshift('-n');
							if (opts.force[0].checked) args.unshift('--force');
							if (opts.skip_orig[0].checked && opts.keep[0].checked) args.unshift('-u');
							ui.showModal(_('Flashing...'), [
								E('p', { 'class': 'spinning' }, _('The system is flashing the new firmware image now. Do not power off the device!'))
							]);
							fs.exec('/sbin/sysupgrade', args);
							ui.awaitReconnect('192.168.1.20', '192.168.1.1', 'openwrt.lan');
						})
					}, [ _('Continue') ])
				])
			]));
		}, this, ev.target)).catch(function(e) {
			ui.addNotification(null, E('p', e.message));
		}).finally(L.bind(function(btn) {
			btn.firstChild.data = _('Flash image...');
		}, this, ev.target));
	},

	render: function(rpc_replies) {
		var has_sysupgrade = (rpc_replies[0].type == 'file'),
		    procmtd = rpc_replies[2] || '',
		    procpart = rpc_replies[3] || '',
		    procmounts = rpc_replies[4] || '',
		    has_rootfs_data = (procmtd.match(/"rootfs_data"/) != null) || (procmounts.match("overlayfs:\\/overlay \\/ ") != null),
		    storage_size = findStorageSize(procmtd, procpart),
		    m, s, o, ss;

		m = new form.JSONMap(mapdata, _('Flash operations'));
		m.tabbed = true;
		m.readonly = isReadonlyView;

		s = m.section(form.NamedSection, 'actions', _('Actions'));

		o = s.option(
			form.SectionValue, 'actions', form.NamedSection, 'actions', 'actions',
			_('Restore'),
			_('To restore configuration files, you can upload a previously generated backup archive here. To reset the firmware to its initial state, click "Perform reset" (only possible with squashfs images).')
		);
		ss = o.subsection;
		if (has_rootfs_data) {
			o = ss.option(form.Button, 'reset', _('Reset to defaults'));
			o.inputstyle = 'negative important';
			o.inputtitle = _('Perform reset');
			o.onclick = this.handleFirstboot;
		}

		o = s.option(
			form.SectionValue, 'actions', form.NamedSection, 'actions', 'actions',
			_('Flash new firmware image'),
			has_sysupgrade
				? _('Upload a sysupgrade-compatible image here to replace the running firmware.')
				: _('Sorry, there is no sysupgrade support present; a new firmware image must be flashed manually. Please refer to the wiki for device specific install instructions.')
		);
		ss = o.subsection;
		if (has_sysupgrade) {
			o = ss.option(form.Button, 'sysupgrade', _('Image'));
			o.inputstyle = 'action important';
			o.inputtitle = _('Flash image...');
			o.onclick = L.bind(this.handleSysupgrade, this, storage_size, has_rootfs_data);
		}

		return m.render();
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
EOF
    echo "✅ تم تخصيص ملف flash.js بنجاح."
fi

# ==========================================
# 11. تخصيص الفوتر (Footer) لثيم Argon (footer.htm و footer_login.htm)
# ==========================================
for FOOTER_FILE in \
    "package/base-files/files/usr/lib/lua/luci/view/themes/argon/footer.htm" \
    "package/luci-theme-argon/luasrc/view/themes/argon/footer.htm" \
    "feeds/luci/themes/luci-theme-argon/luasrc/view/themes/argon/footer.htm"
do
    if [ -f "$FOOTER_FILE" ]; then
        {
            head -n 20 "$FOOTER_FILE"
            cat << 'EOF'
<footer class="mobile-hide" style="position: fixed; bottom: 8px; right: 16px; left: auto; z-index: 10;">
	<div>
		<a href="https://wa.me/+967770528863" style="color: #5e72e4; font-weight: 500;">Powered by Ahosam-WIFI | للتواصل : 770528863</a>
		<ul class="breadcrumb pull-right" id="modemenu" style="display:none"></ul>
	</div>
</footer>
EOF
            tail -n +29 "$FOOTER_FILE"
        } > "${FOOTER_FILE}.tmp" && mv "${FOOTER_FILE}.tmp" "$FOOTER_FILE"
        echo "✅ تم تخصيص $FOOTER_FILE بنجاح."
    fi
done

for FOOTER_LOGIN_FILE in \
    "package/base-files/files/usr/lib/lua/luci/view/themes/argon/footer_login.htm" \
    "package/luci-theme-argon/luasrc/view/themes/argon/footer_login.htm" \
    "feeds/luci/themes/luci-theme-argon/luasrc/view/themes/argon/footer_login.htm"
do
    if [ -f "$FOOTER_LOGIN_FILE" ]; then
        {
            head -n 20 "$FOOTER_LOGIN_FILE"
            cat << 'EOF'
<footer class="mobile-hide">
	<div>
		<a href="https://wa.me/+967770528863" style="color: #5e72e4; font-weight: 500;">Powered by Ahosam-WIFI | للتواصل : 770528863</a>
		<ul class="breadcrumb pull-right" id="modemenu" style="display:none"></ul>
	</div>
</footer>
EOF
            tail -n +29 "$FOOTER_LOGIN_FILE"
        } > "${FOOTER_LOGIN_FILE}.tmp" && mv "${FOOTER_LOGIN_FILE}.tmp" "$FOOTER_LOGIN_FILE"
        echo "✅ تم تخصيص $FOOTER_LOGIN_FILE بنجاح."
    fi
done

# ==========================================
# 11b. إصلاح فتح وإغلاق القائمة الجانبية في الجوال + منع تراكب الفوتر مع أزرار الحفظ
# ==========================================
for ARGON_CSS in \
    "package/base-files/files/www/luci-static/argon/css/cascade.css" \
    "package/luci-theme-argon/htdocs/luci-static/argon/css/cascade.css" \
    "feeds/luci/themes/luci-theme-argon/htdocs/luci-static/argon/css/cascade.css" \
    "package/luci-theme-argon/root/www/luci-static/argon/css/cascade.css" \
    "feeds/luci/themes/luci-theme-argon/root/www/luci-static/argon/css/cascade.css"
do
    if [ -f "$ARGON_CSS" ]; then
        if ! grep -q "mobile-menu-open" "$ARGON_CSS"; then
            cat << 'EOF' >> "$ARGON_CSS"
@media screen and (max-width:768px){
  .main-left.mobile-menu-open{width:15rem!important;display:block!important;position:fixed!important;top:0!important;bottom:0!important;left:0!important;z-index:10001!important;overflow-y:auto!important}
  .mobile-menu-backdrop{display:none;position:fixed;inset:0;background:rgba(0,0,0,0.5);z-index:10000}
  .mobile-menu-backdrop.active{display:block!important}
}
EOF
            echo "✅ تم إضافة CSS القائمة الجانبية للجوال إلى $ARGON_CSS"
        fi
    fi
done

for ARGON_FOOTER in \
    "package/base-files/files/usr/lib/lua/luci/view/themes/argon/footer.htm" \
    "package/luci-theme-argon/luasrc/view/themes/argon/footer.htm" \
    "feeds/luci/themes/luci-theme-argon/luasrc/view/themes/argon/footer.htm"
do
    if [ -f "$ARGON_FOOTER" ] && ! grep -q "mobile-menu-backdrop" "$ARGON_FOOTER"; then
        cat << 'EOF' >> "$ARGON_FOOTER"
<script>
(function() {
	if (window.innerWidth > 768) return;
	function getSidebar() {
		return document.getElementById('mainmenu') || document.querySelector('.main-left');
	}
	function ensureBackdrop() {
		var bd = document.getElementById('mobile-menu-backdrop');
		if (!bd) {
			bd = document.createElement('div');
			bd.id = 'mobile-menu-backdrop';
			bd.className = 'mobile-menu-backdrop';
			document.body.appendChild(bd);
			bd.addEventListener('click', function(e) {
				e.preventDefault();
				e.stopPropagation();
				setMenuState(false);
			});
		}
		return bd;
	}
	function setMenuState(open) {
		var sb = getSidebar();
		if (!sb) return;
		var bd = ensureBackdrop();
		if (open) {
			sb.classList.add('mobile-menu-open');
			bd.classList.add('active');
		} else {
			sb.classList.remove('mobile-menu-open');
			bd.classList.remove('active');
		}
	}
	document.addEventListener('click', function(e) {
		if (window.innerWidth > 768) return;
		var sb = getSidebar();
		if (!sb) return;
		var btn = e.target && e.target.closest ? e.target.closest('a.showSide') : null;
		if (btn) {
			e.preventDefault();
			e.stopPropagation();
			setMenuState(!sb.classList.contains('mobile-menu-open'));
			return;
		}
		if (sb.classList.contains('mobile-menu-open') && !sb.contains(e.target)) {
			setMenuState(false);
		}
	}, true);
})();
</script>
EOF
        echo "✅ تم إضافة JS القائمة الجانبية للجوال إلى $ARGON_FOOTER"
    fi

    if [ -f "$ARGON_FOOTER" ] && ! grep -q "margin-bottom: 75px !important" "$ARGON_FOOTER"; then
        cat << 'EOF' >> "$ARGON_FOOTER"
<style>
.cbi-page-actions {
	position: relative !important;
	z-index: 9999 !important;
	margin-bottom: 75px !important;
}
footer, .footer, #footer, .argon-footer, .hosam-custom-footer {
	position: relative !important;
	z-index: 5 !important;
	clear: both !important;
}
</style>
EOF
        echo "✅ تم إضافة أنماط منع تراكب الفوتر مع أزرار الحفظ إلى $ARGON_FOOTER"
    fi
done

# ==========================================
# 11c. استدعاء menu.js عبر L.require('menu') في header.htm لضمان بناء القوائم تلقائياً
# ==========================================
for ARGON_HEADER in \
    "package/base-files/files/usr/lib/lua/luci/view/themes/argon/header.htm" \
    "package/luci-theme-argon/luasrc/view/themes/argon/header.htm" \
    "feeds/luci/themes/luci-theme-argon/luasrc/view/themes/argon/header.htm"
do
    if [ -f "$ARGON_HEADER" ] && ! grep -q "L.require('menu')" "$ARGON_HEADER"; then
        awk '
        {
            print $0
            if (index($0, "luci.js") > 0 && !done) {
                print "<script>(function(){function initMenu(){if(window.L&&typeof L.require===\"function\"){L.require(\x27menu\x27).then(function(Menu){try{new Menu();}catch(e){}});}else{setTimeout(initMenu,50);}}if(document.readyState===\"loading\"){document.addEventListener(\"DOMContentLoaded\",initMenu);}else{initMenu();}})();</script>"
                done=1
            }
        }
        ' "$ARGON_HEADER" > "${ARGON_HEADER}.tmp" && mv "${ARGON_HEADER}.tmp" "$ARGON_HEADER"
        echo "✅ تم إضافة استدعاء L.require('menu') إلى $ARGON_HEADER"
    fi
done

# ==========================================
# 12. تأكيد تفعيل wpad-mbedtls
# ==========================================
if [ -f .config ]; then
    sed -i '/CONFIG_PACKAGE_wpad-/d' .config
    sed -i '/# CONFIG_PACKAGE_wpad-/d' .config
    cat << 'EOF' >> .config
# CONFIG_PACKAGE_wpad-basic is not set
# CONFIG_PACKAGE_wpad-basic-mbedtls is not set
# CONFIG_PACKAGE_wpad-basic-wolfssl is not set
# CONFIG_PACKAGE_wpad-mini is not set
# CONFIG_PACKAGE_wpad-mini-mbedtls is not set
# CONFIG_PACKAGE_wpad-mini-wolfssl is not set
# CONFIG_PACKAGE_wpad-mesh-mbedtls is not set
# CONFIG_PACKAGE_wpad-mesh-wolfssl is not set
# CONFIG_PACKAGE_wpad-wolfssl is not set
# CONFIG_PACKAGE_wpad-openssl is not set
CONFIG_PACKAGE_wpad-mbedtls=y
EOF
    echo "✅ تم ضبط wpad-mbedtls لتفعيل ميزات 802.11r/k/v."
fi

# ==========================================
# 13. ضبط مستودعات opkg على HTTP لتفادي أخطاء شهادة TLS
# ==========================================
mkdir -p package/base-files/files/etc/uci-defaults
cat << 'EOF' > package/base-files/files/etc/uci-defaults/96-fix-opkg-http
#!/bin/sh
if [ -f /etc/opkg/distfeeds.conf ]; then
    sed -i 's|https://|http://|g' /etc/opkg/distfeeds.conf
fi
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/96-fix-opkg-http

# ==========================================
# 14. إخفاء تبويب Argon Config وتبويب Software من قائمة LuCI نهائياً
# ==========================================
for MENU_FILE in $(find feeds/luci package -path "*/root/usr/share/luci/menu.d/*.json" 2>/dev/null); do
    case "$(basename "$MENU_FILE")" in
        *argon*config*.json|*opkg*.json|*packages*.json)
            rm -f "$MENU_FILE"
            echo "✅ تم حذف ملف قائمة: $MENU_FILE"
            continue
            ;;
    esac
    if grep -qE '"admin/system/opkg"|"admin/system/packages"|"admin/system/argon"|"admin/system/argon-config"' "$MENU_FILE"; then
        awk '
        /"admin\/system\/opkg":/ || /"admin\/system\/packages":/ || /"admin\/system\/argon":/ || /"admin\/system\/argon-config":/ { skip=1; braces=0 }
        skip {
            for (i=1; i<=length($0); i++) {
                c = substr($0, i, 1)
                if (c == "{") braces++
                else if (c == "}") braces--
            }
            if (braces <= 0 && /}/) skip=0
            next
        }
        { print }
        ' "$MENU_FILE" > "$MENU_FILE.tmp" && mv "$MENU_FILE.tmp" "$MENU_FILE"

        sed -i ':a;N;$!ba;s/,\s*\n\s*}/\n}/g' "$MENU_FILE" 2>/dev/null || true
        echo "✅ تم إخفاء العناصر المستهدفة من: $MENU_FILE"
    fi
done

# ==========================================
# 15. دمج إضافة quicksetup_backup.tar.gz داخل الفيرموير
# ==========================================
mkdir -p package/base-files/files
if [ -f "$GITHUB_WORKSPACE/quicksetup_backup.tar.gz" ]; then
    tar -xzf "$GITHUB_WORKSPACE/quicksetup_backup.tar.gz" -C package/base-files/files/
    chmod +x package/base-files/files/etc/init.d/wizard 2>/dev/null || true

    mkdir -p package/base-files/files/etc/uci-defaults
    cat << 'EOF' > package/base-files/files/etc/uci-defaults/95-enable-quicksetup
#!/bin/sh
if [ -x /etc/init.d/wizard ]; then
    /etc/init.d/wizard enable 2>/dev/null || true
    /etc/init.d/wizard start 2>/dev/null || true
fi
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
exit 0
EOF
    chmod +x package/base-files/files/etc/uci-defaults/95-enable-quicksetup
    echo "✅ تم دمج إضافة quicksetup وتفعيل خدمة wizard بنجاح."
else
    echo "⚠️ تحذير: لم يتم العثور على ملف quicksetup_backup.tar.gz في المستودع."
fi

# ==========================================
# 16. استبدال صورة argon.svg داخل حزمة luci-theme-argon (بدون تعارض مع base-files)
# ==========================================
rm -f package/base-files/files/www/luci-static/argon/img/argon.svg 2>/dev/null || true
ARGON_SVG_SRC="$GITHUB_WORKSPACE/argon.svg"
if [ -f "$ARGON_SVG_SRC" ]; then
    UPDATED_SVG=0
    for SVG_TARGET in \
        "package/luci-theme-argon/htdocs/luci-static/argon/img/argon.svg" \
        "feeds/luci/themes/luci-theme-argon/htdocs/luci-static/argon/img/argon.svg" \
        "package/luci-theme-argon/root/www/luci-static/argon/img/argon.svg" \
        "feeds/luci/themes/luci-theme-argon/root/www/luci-static/argon/img/argon.svg"
    do
        if [ -f "$SVG_TARGET" ]; then
            cp -f "$ARGON_SVG_SRC" "$SVG_TARGET"
            echo "✅ تم تحديث: $SVG_TARGET"
            UPDATED_SVG=1
        fi
    done

    if [ "$UPDATED_SVG" -eq 0 ]; then
        echo "⚠️ لم يُعثر على ملف argon.svg داخل شجرة luci-theme-argon."
    fi
else
    echo "⚠️ تحذير: لم يتم العثور على ملف argon.svg في $GITHUB_WORKSPACE."
fi

# ==========================================
# 17. تسلسل إضاءة LEDs عند الإقلاع والاستقرار وضبط المؤشرات + DTS
# ==========================================
echo "🔍 البحث عن ملفات DTS الخاصة باللمبات والجهاز..."
DTS_TARGET="target/linux/ramips/dts/mt7621_xiaomi_mi-router-cr660x.dtsi"
DTS_FILES=$(grep -rnE "yellow:sys|yellow:net|blue:sys|blue:net" target/linux/ramips/dts/ 2>/dev/null | cut -d: -f1 | sort -u)
if [ -f "$DTS_TARGET" ]; then
    DTS_FILES="$DTS_TARGET $DTS_FILES"
fi
DTS_FILES=$(printf "%s\n" $DTS_FILES | awk '!seen[$0]++')

for dts in $DTS_FILES; do
    if [ -f "$dts" ]; then
        echo "🔧 تعديل ملف DTS للـ LEDs: $dts"
        python3 - "$dts" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, "r", encoding="utf-8", errors="ignore") as f:
    content = f.read()

def patch_single_led(match):
    prefix = match.group(1)
    body = match.group(2)
    suffix = match.group(3)

    if re.search(r'label\s*=\s*"yellow:(sys|net)"', body):
        if re.search(r'default-state\s*=', body):
            body = re.sub(r'default-state\s*=\s*"[^"]*"\s*;', 'default-state = "on";', body)
        else:
            body = body.rstrip() + '\n\t\t\tdefault-state = "on";\n\t\t'
    elif re.search(r'label\s*=\s*"blue:(sys|net)"', body):
        if re.search(r'default-state\s*=', body):
            body = re.sub(r'default-state\s*=\s*"[^"]*"\s*;', 'default-state = "off";', body)
        else:
            body = body.rstrip() + '\n\t\t\tdefault-state = "off";\n\t\t'

    return f"{prefix}{body}{suffix}"

pattern = re.compile(r'(\n\t+[a-zA-Z0-9_-]+\s*\{)(.*?)(\n\t+\};)', re.DOTALL)
new_content = pattern.sub(patch_single_led, content)

if new_content != content:
    with open(path, "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"   ✅ تم ضبط البرتقالي (on) والأزرق (off) في {path}")
else:
    print(f"   ℹ️ لم يتم تغيير أي شيء في {path}")
PYEOF
    fi
done

mkdir -p package/base-files/files/usr/bin
cat << 'EOF' > package/base-files/files/usr/bin/promax-led-boot.sh
#!/bin/sh

LED_Y1="yellow:sys"
LED_Y2="yellow:net"
LED_B1="blue:sys"
LED_B2="blue:net"

max_val() {
    local led="$1"
    if [ -f "/sys/class/leds/$led/max_brightness" ]; then
        cat "/sys/class/leds/$led/max_brightness"
    else
        echo 255
    fi
}

set_led() {
    local led="$1"
    local trig="$2"
    local val="$3"
    [ -d "/sys/class/leds/$led" ] || return 0
    if [ -n "$trig" ] && [ -f "/sys/class/leds/$led/trigger" ]; then
        echo "$trig" > "/sys/class/leds/$led/trigger" 2>/dev/null || true
    fi
    if [ -n "$val" ] && [ -f "/sys/class/leds/$led/brightness" ]; then
        echo "$val" > "/sys/class/leds/$led/brightness" 2>/dev/null || true
    fi
}

wait_step() {
    if command -v usleep >/dev/null 2>&1; then
        usleep 250000
    else
        sleep 1
    fi
}

set_wan_blue_link_only() {
    [ -d "/sys/class/leds/$LED_B2" ] || return 0
    echo 0 > "/sys/class/leds/$LED_B2/brightness" 2>/dev/null || true

    if [ -f "/sys/class/leds/$LED_B2/trigger" ]; then
        WAN_TRIG=$(tr ' ' '\n' < "/sys/class/leds/$LED_B2/trigger" | tr -d '[]' | tr '\t' '\n' | grep -E 'mt7530.*:04:link|mt7530.*:00:link|mt7530.*:link' | head -n 1)
        if [ -n "$WAN_TRIG" ]; then
            echo "$WAN_TRIG" > "/sys/class/leds/$LED_B2/trigger" 2>/dev/null || true
            return 0
        fi
    fi
    echo "none" > "/sys/class/leds/$LED_B2/trigger" 2>/dev/null || true
    echo 0 > "/sys/class/leds/$LED_B2/brightness" 2>/dev/null || true
}

(
    VY1=$(max_val "$LED_Y1")
    VY2=$(max_val "$LED_Y2")
    VB1=$(max_val "$LED_B1")

    # 1) تشغيل اللمبتين البرتقاليتين معاً لمدة ثانيتين فقط
    set_led "$LED_B1" "none" 0
    set_led "$LED_B2" "none" 0
    set_led "$LED_Y1" "none" "$VY1"
    set_led "$LED_Y2" "none" "$VY2"
    sleep 2

    # 2) إطفاء لمبة WAN البرتقالية (yellow:net) فوراً وتثبيتها مطفأة، مع إبقاء اللمبة الأساسية (yellow:sys) تومض
    set_led "$LED_Y2" "none" 0
    set_led "$LED_Y1" "none" 0

    i=0
    while [ $i -lt 10 ]; do
        set_led "$LED_Y2" "none" 0
        echo "$VY1" > "/sys/class/leds/$LED_Y1/brightness" 2>/dev/null || true
        wait_step
        echo 0 > "/sys/class/leds/$LED_Y1/brightness" 2>/dev/null || true
        wait_step
        i=$((i + 1))
    done

    # 3) الاستقرار: إطفاء البرتقالي نهائياً، وتشغيل الأزرق الثابت لللمبة الأساسية (blue:sys)
    set_led "$LED_Y1" "none" 0
    set_led "$LED_Y2" "none" 0

    set_led "$LED_B1" "default-on" "$VB1"
    if [ ! -f "/sys/class/leds/$LED_B1/trigger" ]; then
        echo "$VB1" > "/sys/class/leds/$LED_B1/brightness" 2>/dev/null || true
    fi

    set_wan_blue_link_only

    sleep 3
    set_led "$LED_Y1" "none" 0
    set_led "$LED_Y2" "none" 0
    set_led "$LED_B1" "default-on" "$VB1"
    set_wan_blue_link_only
) >/dev/null 2>&1 &
exit 0
EOF
chmod +x package/base-files/files/usr/bin/promax-led-boot.sh

cat << 'EOF' > package/base-files/files/etc/uci-defaults/99-promax-led
#!/bin/sh
if uci -q get system.led_internet >/dev/null 2>&1; then
    uci -q delete system.led_internet
    uci commit system
fi
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-promax-led

if [ -f package/base-files/files/etc/rc.local ]; then
    if ! grep -q "promax-led-boot.sh" package/base-files/files/etc/rc.local; then
        sed -i '/exit 0/i /usr/bin/promax-led-boot.sh' package/base-files/files/etc/rc.local
    fi
fi
echo "✅ تم إعداد تسلسل LEDs وتعديل ملفات DTS بنجاح."

# ==========================================
# 18. جلب حزمة luci-app-lldpd وتثبيتها على فرع 22.03 إن لم تكن موجودة
# ==========================================
if [ ! -d "feeds/luci/applications/luci-app-lldpd" ]; then
    echo "🔍 جاري جلب luci-app-lldpd من مستودع OpenWrt..."
    rm -rf /tmp/luci-lldpd-tmp
    git clone --depth 1 --filter=blob:none --sparse https://git.openwrt.org/project/luci.git /tmp/luci-lldpd-tmp 2>/dev/null || true
    if [ -d "/tmp/luci-lldpd-tmp" ]; then
        git -C /tmp/luci-lldpd-tmp sparse-checkout set applications/luci-app-lldpd
        if [ -d "/tmp/luci-lldpd-tmp/applications/luci-app-lldpd" ]; then
            cp -rf /tmp/luci-lldpd-tmp/applications/luci-app-lldpd feeds/luci/applications/luci-app-lldpd
            ./scripts/feeds update -i luci 2>/dev/null || true
            ./scripts/feeds install -p luci luci-app-lldpd 2>/dev/null || true
            echo "✅ تم تثبيت حزمة luci-app-lldpd في feeds/luci بنجاح."
        else
            echo "⚠️ تعذر استخراج مجلد luci-app-lldpd."
        fi
        rm -rf /tmp/luci-lldpd-tmp
    else
        echo "⚠️ تعذر الاتصال بمستودع luci لجلب luci-app-lldpd."
    fi
fi

if [ -f .config ]; then
    grep -q "^CONFIG_PACKAGE_lldpd=" .config || echo "CONFIG_PACKAGE_lldpd=y" >> .config
    grep -q "^CONFIG_PACKAGE_luci-app-lldpd=" .config || echo "CONFIG_PACKAGE_luci-app-lldpd=y" >> .config
fi
