#!/bin/sh

KERNEL="vulture-hardenedbsd"
KERNEL_TOOLS="vulture-hardenedbsd-tools"

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

bsd_version=$(/usr/bin/uname -r | /usr/bin/cut -d '-' -f 1)

base_url="https://download.vultureproject.org/v4/${bsd_version}/kernel/${KERNEL}"
/bin/rm -f /var/tmp/${KERNEL}.txz
/usr/local/bin/wget "$base_url-latest.txz" -O /var/tmp/${KERNEL}.txz
/usr/local/bin/wget "$base_url-latest.sha256sum" -O /var/tmp/${KERNEL}.sha256sum
/bin/echo -n "Verifying SHASUM for ${KERNEL}.txz... "
/sbin/sha256 -c /var/tmp/${KERNEL}.sha256sum > /dev/null
if [ "$?" == "0" ]; then
    /bin/echo "Ok!"
else
    /bin/echo "Bad shasum for ${KERNEL}.txz"
	exit
fi

base_url="https://download.vultureproject.org/v4/${bsd_version}/kernel/${KERNEL_TOOLS}"
/bin/rm -f /var/tmp/${KERNEL_TOOLS}.txz
/usr/local/bin/wget "$base_url-latest.txz" -O /var/tmp/${KERNEL_TOOLS}.txz
/usr/local/bin/wget "$base_url-latest.sha256sum" -O /var/tmp/${KERNEL_TOOLS}.sha256sum
/bin/echo -n "Verifying SHASUM for ${KERNEL_TOOLS}.txz... "
/sbin/sha256 -c /var/tmp/${KERNEL_TOOLS}.sha256sum > /dev/null
if [ "$?" == "0" ]; then
    /bin/echo "Ok!"
else
    /bin/echo "Bad shasum for ${KERNEL_TOOLS}.txz"
	exit
fi

/usr/bin/tar xvf /var/tmp/${KERNEL}.txz -C /boot/
/usr/bin/tar xvf /var/tmp/${KERNEL_TOOLS}.txz -C /

/bin/rm -f /var/tmp/${KERNEL}.txz
/bin/rm -f /var/tmp/${KERNEL_TOOLS}.txz

cp /usr/lib/libhbsdcontrol.so.0 /zroot/apache/usr/lib/libhbsdcontrol.so.0
cp /usr/sbin/hbsdcontrol /zroot/apache/usr/sbin/hbsdcontrol
