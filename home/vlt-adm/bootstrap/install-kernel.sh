#!/bin/sh

KERNEL="vulture-hardenedbsd"

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

bsd_version=$(/usr/bin/uname -r | /usr/bin/cut -d '-' -f 1)
bsd_os=$(/usr/bin/uname -i | /usr/bin/cut -d '-' -f 1)

if [ "${bsd_os}" != "HARDENEDBSD" ]; then
    /bin/echo "!!! WARNING !!!"
    /bin/echo "You are about to break your system !"
    /bin/echo "No kernel is available for your Operating System"
    exit 1
fi

base_url="https://download.vultureproject.org/v4/${bsd_version}/kernel/${KERNEL}"
/bin/rm -f /var/tmp/${KERNEL}.txz
/usr/local/bin/wget "$base_url-latest.txz" -O /var/tmp/${KERNEL}.txz
/usr/local/bin/wget "$base_url-latest.sha256sum" -O /var/tmp/${KERNEL}.sha256sum
/bin/echo -n "Verifying SHASUM for ${KERNEL}.txz... "
/sbin/sha256 -c `cat /var/tmp/${KERNEL}.sha256sum | cut -d ' ' -f 1` /var/tmp/${KERNEL}.sha256sum > /dev/null
if [ "$?" == "0" ]; then
    /bin/echo "Ok!"
else
    /bin/echo "Bad shasum for ${KERNEL}.txz"
	exit
fi

/usr/bin/tar xvf /var/tmp/${KERNEL}.txz -C /
/bin/rm -f /var/tmp/${KERNEL}.txz


# Don't install mbr if disk is not using encryption as it will break EFI system
geli list | grep 'p3\.eli' 2> /dev/null
if [ "$?" == "0" ]; then
    # Update GPTZFSBoot with latest image
    sysctl kern.geom.confdot | sed -n 's/^.*hexagon,label="\([^\]*\)\\n\([^\]*\).*/\1 \2/p' | grep '0 .*' |sed 's/ .*//' |grep -v '^cd'|grep -v '^gpt' > /tmp/DISKSLICE_$$
    DISKSLICE=`cat /tmp/DISKSLICE_$$`
    echo "Install Vulture-OS bootcode on ${DISKSLICE}"
    gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 ${DISKSLICE}
fi

# Restart secadm after rules update
/usr/sbin/service secadm restart
