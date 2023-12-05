#!/usr/bin/env ash

# https://github.com/xbl3/synocodectool-patch

if [ "${1}" = "late" ]; then
  echo "Installing addon synocodec patch"
  cp -v /usr/bin/codecpatch.sh /tmpRoot/usr/bin/codecpatch.sh

  DEST="/tmpRoot/usr/lib/systemd/system/codecpatch.service"
  echo "[Unit]"                               >${DEST}
  echo "Description=Patch synocodectool"     >>${DEST}
  echo "After=multi-user.target"             >>${DEST}
  echo                                       >>${DEST}
  echo "[Service]"                           >>${DEST}
  echo "Type=oneshot"                        >>${DEST}
  echo "RemainAfterExit=true"                >>${DEST}
  echo "ExecStart=/usr/bin/codecpatch.sh"    >>${DEST}
  echo                                       >>${DEST}
  echo "[Install]"                           >>${DEST}
  echo "WantedBy=multi-user.target"          >>${DEST}

  mkdir -vp /tmpRoot/lib/systemd/system/multi-user.target.wants
  ln -vsf /usr/lib/systemd/system/codecpatch.service /tmpRoot/lib/systemd/system/multi-user.target.wants/codecpatch.service
fi
