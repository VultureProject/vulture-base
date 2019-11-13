#!/bin/sh

KERNEL="vulture-hardenedbsd"

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

bsd_version=$(/usr/bin/uname -r | /usr/bin/cut -d '-' -f 1)
base_url="https://download.vultureproject.org/v4/${bsd_version}/kernel/${KERNEL}"
/bin/rm -f /var/tmp/${KERNEL}.txz
/usr/local/bin/wget "$base_url-latest.txz" -O /var/tmp/${KERNEL}.txz
/usr/local/bin/wget "$base_url.sha256sum" -O /var/tmp/${KERNEL}.sha256sum

/bin/echo -n "Verifying SHASUM for ${KERNEL}.txz... "
/sbin/sha256 -c /var/tmp/${KERNEL}.sha256sum > /dev/null
if [ "$?" == "0" ]; then
    /bin/echo "Ok!"
else
    /bin/echo "Bad shasum for ${KERNEL}.txz"
	exit
fi

/usr/bin/tar xvf /var/tmp/${KERNEL}.txz -C /boot/
/bin/rm -f /var/tmp/${KERNEL}.txz
