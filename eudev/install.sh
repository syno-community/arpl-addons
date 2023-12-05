#!/usr/bin/env ash

# DSM version
MajorVersion=`/bin/get_key_value /etc.defaults/VERSION majorversion`
MinorVersion=`/bin/get_key_value /etc.defaults/VERSION minorversion`
echo "MajorVersion:${MajorVersion} MinorVersion:${MinorVersion}"

if [ "${1}" = "modules" ]; then
	echo "Starting eudev daemon - modules"
	if [ "${MajorVersion}" -lt "7" ]; then # < 7
		tar zxf /addons/eudev-6.2.tgz -C /
	else
		if [ "${MinorVersion}" -lt "2" ]; then # < 2
			tar zxf /addons/eudev-7.1.tgz -C /
		else
			tar zxf /addons/eudev-7.2.tgz -C /
		fi
	fi
	[ -e /proc/sys/kernel/hotplug ] && printf '\000\000\000\000' > /proc/sys/kernel/hotplug
	chmod 755 /usr/sbin/udevd /usr/bin/kmod /usr/bin/udevadm /usr/lib/udev/*
	/usr/sbin/udevd -d || { echo "FAIL"; exit 1; }
	echo "Triggering add events to udev"
	udevadm trigger --type=subsystems --action=add
	udevadm trigger --type=devices --action=add
	udevadm trigger --type=devices --action=change
	udevadm settle --timeout=30 || echo "udevadm settle failed"
	# Give more time
	sleep 10
	# Remove from memory to not conflict with RAID mount scripts
	/usr/bin/killall udevd
elif [ "${1}" = "late" ]; then
	echo "Starting eudev daemon - late"
	# Copy rules
	cp -vf /usr/lib/udev/rules.d/* /tmpRoot/usr/lib/udev/rules.d/
	if [ "${MajorVersion}" -lt "7" ]; then # < 7
		mkdir -p /tmpRoot/etc/init
		DEST=/tmpRoot/etc/init/eudev.conf
		echo 'description "EUDEV daemon"'                                              >${DEST}
		echo 'System Intergration Team'                                               >>${DEST}
		echo 'start on runlevel 1'                                                    >>${DEST}
		echo 'stop on runlevel [06]'                                                  >>${DEST}
		echo 'expect fork'                                                            >>${DEST}
		echo 'respawn'                                                                >>${DEST}
		echo 'respawn limit 5 10'                                                     >>${DEST}
		echo 'console log'                                                            >>${DEST}
		echo 'exec /usr/bin/udevadm hwdb --update'                                    >>${DEST}
		echo 'exec /usr/bin/udevadm control --reload-rules'                           >>${DEST}
	else
		DEST="/tmpRoot/lib/systemd/system/udevrules.service"
		echo "[Unit]"                                                                  >${DEST}
		echo "Description=Reload udev rules"                                          >>${DEST}
		echo                                                                          >>${DEST}
		echo "[Service]"                                                              >>${DEST}
		echo "Type=oneshot"                                                           >>${DEST}
		echo "RemainAfterExit=true"                                                   >>${DEST}
		echo "ExecStart=/usr/bin/udevadm hwdb --update"                               >>${DEST}
		echo "ExecStart=/usr/bin/udevadm control --reload-rules"                      >>${DEST}
		echo                                                                          >>${DEST}
		echo "[Install]"                                                              >>${DEST}
		echo "WantedBy=multi-user.target"                                             >>${DEST}

		mkdir -vp /tmpRoot/lib/systemd/system/multi-user.target.wants
		ln -vsf /lib/systemd/system/udevrules.service /tmpRoot/lib/systemd/system/multi-user.target.wants/udevrules.service
	fi
fi

