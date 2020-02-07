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
/usr/local/bin/wget "$base_url-latest.sha256sum" -O /var/tmp/${KERNEL}.sha256sum
/bin/echo -n "Verifying SHASUM for ${KERNEL}.txz... "
/sbin/sha256 -c /var/tmp/${KERNEL}.sha256sum > /dev/null
if [ "$?" == "0" ]; then
    /bin/echo "Ok!"
else
    /bin/echo "Bad shasum for ${KERNEL}.txz"
	exit
fi

/usr/bin/tar xvf /var/tmp/${KERNEL}.txz -C /
/bin/rm -f /var/tmp/${KERNEL}.txz

#Update GPTZFSBoot with latest image
sysctl kern.geom.confdot | sed -n 's/^.*hexagon,label="\([^\]*\)\\n\([^\]*\).*/\1 \2/p' | grep '0 .*' |sed 's/ .*//' |grep -v '^cd'|grep -v '^gpt' > /tmp/DISKSLICE_$$
DISKSLICE=`cat /tmp/DISKSLICE_$$`
echo "Install Vulture-OS bootcode on ${DISKSLICE}"
gpart bootcode -b /mnt/boot/pmbr -p /mnt/boot/gptzfsboot -i 1 ${DISKSLICE}

chown -R root:wheel /usr/lib/ /usr/sbin/ /usr/local/lib
chown root:wheel /usr/local
service ldconfig restart

sysrc secadm_enable=YES
service secadm restart

#Deploy secadm in Apache jail
cp /usr/local/etc/secadm.rules /zroot/apache/usr/local/etc/
cp /usr/local/lib/libsecadm.so.1 /zroot/apache/usr/local/lib/
cp /usr/local/sbin/secadm /zroot/apache/usr/local/sbin/

cp /usr/local/etc/secadm-apache.rules /zroot/apache/usr/local/etc/secadm.rules
cp /usr/local/etc/rc.d/secadm /zroot/apache/usr/local/etc/rc.d/
jexec apache chown -R root:wheel /usr/lib/ /usr/sbin/ /usr/local/lib
jexec apache chown root:wheel /usr/local
jexec apache service ldconfig restart
jexec apache sysrc secadm_enable=YES
jexec apache service secadm restart
