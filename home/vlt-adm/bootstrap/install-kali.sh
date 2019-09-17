#!/bin/sh

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

if [ -f /etc/rc.conf.proxy ]; then
    . /etc/rc.conf.proxy
    export http_proxy=${http_proxy}
    export https_proxy=${https_proxy}
    export ftp_proxy=${ftp_proxy}
fi


##########################################################################################

NB_CPU=`/sbin/sysctl -n hw.ncpu`
NB_RAM_TOTAL=`/sbin/sysctl -n hw.physmem`
NB_RAM_GB=`/bin/expr ${NB_RAM_TOTAL} / 1024000000`
NB_RAM=`/bin/expr ${NB_RAM_GB} - 2`

VM_IMAGE="https://download.vultureproject.org/v4/12.0/release/mysoc-kali.img.gz"
VM_NAME="Kali"
VM_TYPE="debian"

##########################################################################################

sysrc vm_list="Kali `sysrc -n vm_list`"
/usr/local/sbin/vm init
/usr/local/sbin/vm create -t ${VM_TYPE} -s 1 ${VM_NAME}

sed -i '' "s/cpu=.*/cpu=${NB_CPU}/" /vms/${VM_NAME}/${VM_NAME}.conf
sed -i '' "s/memory=.*/memory=${NB_RAM}G/" /vms/${VM_NAME}/${VM_NAME}.conf

fetch ${VM_IMAGE} -o - | gunzip > /vms/${VM_NAME}/disk0.img

vm start ${VM_NAME}