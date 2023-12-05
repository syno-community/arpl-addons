
PCI_ER="^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]{1}"

# Get values in synoinfo.conf K=V file
# 1 - key
function _get_conf_kv() {
  grep "${1}=" /etc/synoinfo.conf | sed "s|^${1}=\"\(.*\)\"$|\1|g"
}

# Replace/add values in synoinfo.conf K=V file
# Args: $1 rd|hd, $2 key, $3 val
function _set_conf_kv() {
  local ROOT
  local FILE
  [ "$1" = "rd" ] && ROOT="" || ROOT="/tmpRoot"
  for SD in etc etc.defaults; do
    FILE="${ROOT}/${SD}/synoinfo.conf"
    # Replace
    if grep -q "^$2=" ${FILE}; then
      sed -i ${FILE} -e "s\"^$2=.*\"$2=\\\"$3\\\"\""
    else
      # Add if doesn't exist
      echo "$2=\"$3\"" >> ${FILE}
    fi
  done
}

# Check if the user has customized the key
# Args: $1 rd|hd, $2 key
function _check_post_k() {
  local ROOT
  [ "$1" = "rd" ] && ROOT="" || ROOT="/tmpRoot"
  if grep -q -r "^_set_conf_kv.*${2}.*" "${ROOT}/sbin/init.post"; then
    return 0  # true
  else
    return 1  # false
  fi
}

# Check if the raid has been completed currently
function _check_rootraidstatus() {
  if [ "`_get_conf_kv supportraid`" != "yes" ]; then
    return 0
  fi
  State=$(cat /sys/block/md0/md/array_state) 2>/dev/null
  if [ $? != 0 ]; then
    return 1
  fi
  case ${State} in
    "clear" | "inactive" | "suspended " | "readonly" | "read-auto")
    return 1
  ;;
  esac
  return 0
}

# Calculate # 0 bits
function getNum0Bits() {
  local VALUE=$1
  local NUM=0
  while [ $((${VALUE}%2)) -eq 0 -a ${VALUE} -ne 0 ]; do
    NUM=$((${NUM}+1))
    VALUE=$((${VALUE}/2))
  done
  echo ${NUM}
}

# USB ports
function getUsbPorts() {
  for I in `ls -d /sys/bus/usb/devices/usb*`; do
    # ROOT
    DCLASS=`cat ${I}/bDeviceClass`
    [ "${DCLASS}" != "09" ] && continue
    SPEED=`cat ${I}/speed`
    [ ${SPEED} -lt 480 ] && continue
    RBUS=`cat ${I}/busnum`
    RCHILDS=`cat ${I}/maxchild`
    HAVE_CHILD=0
    for C in `seq 1 ${RCHILDS}`; do
      SUB="${RBUS}-${C}"
      if [ -d "${I}/${SUB}" ]; then
        DCLASS=`cat ${I}/${SUB}/bDeviceClass`
        [ "${DCLASS}" != "09" ] && continue
        SPEED=`cat ${I}/${SUB}/speed`
        [ ${SPEED} -lt 480 ] && continue
        CHILDS=`cat ${I}/${SUB}/maxchild`
        HAVE_CHILD=1
        for N in `seq 1 ${CHILDS}`; do
          echo -n "${RBUS}-${C}.${N} "
        done
      fi
    done
    if [ ${HAVE_CHILD} -eq 0 ]; then
      for N in `seq 1 ${RCHILDS}`; do
        echo -n "${RBUS}-${N} "
      done
    fi
  done
  echo
}

# SATA ports
# 1 - is DT model
function getSataPorts() {
  local SATA_PORTS=`ls /sys/class/ata_port | wc -w`
  local OUTPUT=""
  for I in `seq 1 ${SATA_PORTS}`; do
    DUMMY=$((1-`cat /sys/class/ata_port/ata${I}/device/host*/scsi_host/host*/syno_port_thaw`))
    # Is DT
    if [ "${1}" = "true" ]; then
      [ ${DUMMY} -eq 1 ] && continue
      PORTNO=`cat /sys/class/ata_port/ata${I}/port_no`
      _PATH=`readlink /sys/class/ata_port/ata${I} | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2-`
      DSMPATH=""
      while true; do
        FIRST=`echo "${_PATH}" | cut -d'/' -f1`
        echo "${FIRST}" | grep -qE "${PCI_ER}" || break
        [ -z "${DSMPATH}" ] && \
          DSMPATH="`echo "${FIRST}" | cut -d':' -f2-`" || \
          DSMPATH="${DSMPATH},`echo "${FIRST}" | cut -d':' -f3`"
        _PATH=`echo ${_PATH} | cut -d'/' -f2-`
      done
      echo -n "${DSMPATH}:${PORTNO} "
    else
      if [ ${DUMMY} -eq 1 ]; then
        OUTPUT="0${OUTPUT}"
      else
        OUTPUT="1${OUTPUT}"
      fi
    fi
  done
  echo "${OUTPUT}"
}

# NVME ports
# 1 - is DT model
function nvmePorts() {
  local NVME_PORTS=`ls /sys/class/nvme | wc -w`
  for I in `seq 0 $((${NVME_PORTS}-1))`; do
    _PATH=`readlink /sys/class/nvme/nvme${I} | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2-`
    if [ "${1}" = "true" ]; then
      # Device-tree: assemble complete path in DSM format
      DSMPATH=""
      while true; do
        FIRST=`echo "${_PATH}" | cut -d'/' -f1`
        echo "${FIRST}" | grep -qE "${PCI_ER}" || break
        [ -z "${DSMPATH}" ] && \
          DSMPATH="`echo "${FIRST}" | cut -d':' -f2-`" || \
          DSMPATH="${DSMPATH},`echo "${FIRST}" | cut -d':' -f3`"
        _PATH=`echo ${_PATH} | cut -d'/' -f2-`
      done
    else
      # Non-dt: just get PCI ID
      DSMPATH=`echo "${_PATH}" | cut -d'/' -f1`
    fi
    echo -n "${DSMPATH} "
  done
  echo
}

#
function dtModel() {
  DEST="/addons/model.dts"
  if [ ! -f "${DEST}" ]; then  # Users can put their own dts.
    echo "/dts-v1/;"                                                 > ${DEST}
    echo "/ {"                                                      >> ${DEST}
    echo "    compatible = \"Synology\";"                           >> ${DEST}
    echo "    model = \"${1}\";"                                    >> ${DEST}
    echo "    version = <0x01>;"                                    >> ${DEST}
    # SATA ports
    I=1
    while true; do
      [ ! -d /sys/block/sata${I} ] && break
      PCIEPATH=`grep 'pciepath' /sys/block/sata${I}/device/syno_block_info | cut -d'=' -f2`
      ATAPORT=`grep 'ata_port_no' /sys/block/sata${I}/device/syno_block_info | cut -d'=' -f2`
      echo "    internal_slot@${I} {"                               >> ${DEST}
      echo "        protocol_type = \"sata\";"                      >> ${DEST}
      echo "        ahci {"                                         >> ${DEST}
      echo "            pcie_root = \"${PCIEPATH}\";"               >> ${DEST}
      echo "            ata_port = <0x`printf '%02X' ${ATAPORT}`>;" >> ${DEST}
      echo "        };"                                             >> ${DEST}
      echo "    };"                                                 >> ${DEST}
      I=$((${I}+1))
    done
    NUMPORTS=$((${I}-1))
    if [ $NUMPORTS -eq 1 ]; then
      # fix isSingleBay issue:
      #   if maxdisks is 1, there is no create button in the storage panel
      NUMPORTS=2
    fi
    _set_conf_kv rd "maxdisks" "${NUMPORTS}"
    echo "maxdisks=${NUMPORTS}"

    # NVME ports
    COUNT=1
    for P in `nvmePorts true`; do
      echo "    nvme_slot@${COUNT} {"                               >> ${DEST}
      echo "        pcie_root = \"${P}\";"                          >> ${DEST}
      echo "        port_type = \"ssdcache\";"                      >> ${DEST}
      echo "    };"                                                 >> ${DEST}
      COUNT=$((${COUNT}+1))
    done

    # USB ports
    COUNT=1
    for I in `getUsbPorts`; do
      echo "    usb_slot@${COUNT} {"                                >> ${DEST}
      echo "      usb2 {"                                           >> ${DEST}
      echo "        usb_port =\"${I}\";"                            >> ${DEST}
      echo "      };"                                               >> ${DEST}
      echo "      usb3 {"                                           >> ${DEST}
      echo "        usb_port =\"${I}\";"                            >> ${DEST}
      echo "      };"                                               >> ${DEST}
      echo "    };"                                                 >> ${DEST}
      COUNT=$((${COUNT}+1))
    done
    echo "};"                                                       >> ${DEST}
  fi
  dtc -I dts -O dtb ${DEST} > /etc/model.dtb
  cp -fv /etc/model.dtb /run/model.dtb
  /usr/syno/bin/syno_slot_mapping
}

#
function nondtModel() {
  local SATA_PORTS=0
  local SAS_PORTS=0
  local NUMPORTS=0
  local ESATAPORTCFG=$((`_get_conf_kv esataportcfg`))
  local INTPORTCFG
  local USBPORTCFG=$((`_get_conf_kv usbportcfg`))
  local COUNT=1
  if _check_post_k "rd" "maxdisks"; then
    NUMPORTS=$((`_get_conf_kv maxdisks`))
    echo "get maxdisks=${NUMPORTS}"
  else
    # sysfs is populated here
    SATA_PORTS=`ls /sys/class/ata_port | wc -w`
    [ -d '/sys/class/sas_phy' ] && SAS_PORTS=`ls /sys/class/sas_phy | wc -w`
    [ -d '/sys/class/scsi_disk' ] && SCSI_PORTS=`ls /sys/class/scsi_disk | wc -w`
    NUMPORTS=$((${SATA_PORTS}+${SAS_PORTS}+${SCSI_PORTS}))
    # Raidtool will read maxdisks, but when maxdisks is greater than 27, formatting error will occur 8%.
    if ! _check_rootraidstatus && [ ${NUMPORTS} -gt 26 ]; then
      _set_conf_kv rd "maxdisks" "26"
      echo "set maxdisks=26"
    else
      _set_conf_kv rd "maxdisks" "${NUMPORTS}"
      echo "set maxdisks=${NUMPORTS}"
    fi
  fi
  if ! _check_post_k "rd" "internalportcfg"; then
    INTPORTCFG="0x`printf "%x" $((2**${NUMPORTS}-1-${ESATAPORTCFG}))`"
    _set_conf_kv rd "internalportcfg" "${INTPORTCFG}"
    echo "set internalportcfg=${INTPORTCFG}"
    echo "get esataportcfg=${ESATAPORTCFG}"
  fi
  if ! _check_post_k "rd" "internalportcfg"; then
    # USB ports static, always 4 ports
    USBPORT_IDX=`getNum0Bits ${USBPORTCFG}`
    [ ${USBPORT_IDX} -lt ${NUMPORTS} ] && USBPORT_IDX=${NUMPORTS}
    USBPORTCFG="0x`printf '%x' $((15*2**${USBPORT_IDX}))`"
    _set_conf_kv rd "usbportcfg" "${USBPORTCFG}"
    echo "set usbportcfg=${USBPORTCFG}"
  fi
  # NVME
  rm -f /etc/extensionPorts
  echo "[pci]" > /etc/extensionPorts
  chmod 755 /etc/extensionPorts
  for P in `nvmePorts false`; do
    echo "pci${COUNT}=\"${P}\"" >> /etc/extensionPorts
    COUNT=$((${COUNT}+1))
  done
}

#
if [ "${1}" = "patches" ]; then
  echo "Adjust disks related configs automatically - patches"
  [ "${2}" = "true" ] && dtModel ${3} || nondtModel

elif [ "${1}" = "late" ]; then
  echo "Adjust disks related configs automatically - late"
  if [ "${2}" = "true" ]; then
    echo "Copying /etc.defaults/model.dtb"
    # copy file
    cp -vf /etc/model.dtb /tmpRoot/etc/model.dtb
    cp -vf /etc/model.dtb /tmpRoot/etc.defaults/model.dtb
  else
    echo "Adjust maxdisks and internalportcfg automatically"
    # sysfs is unpopulated here, get the values from junior synoinfo.conf
    NUMPORTS=`_get_conf_kv maxdisks`
    INTPORTCFG=`_get_conf_kv internalportcfg`
    USBPORTCFG=`_get_conf_kv usbportcfg`
    _set_conf_kv hd "maxdisks" "${NUMPORTS}"
    _set_conf_kv hd "internalportcfg" "${INTPORTCFG}"
    _set_conf_kv hd "usbportcfg" "${USBPORTCFG}"
    # log
    echo "maxdisks=${NUMPORTS}"
    echo "internalportcfg=${INTPORTCFG}"
    echo "usbportcfg=${USBPORTCFG}"
    cp -vf /etc/extensionPorts /tmpRoot/etc/extensionPorts
    cp -vf /etc/extensionPorts /tmpRoot/etc.defaults/extensionPorts
  fi
fi
