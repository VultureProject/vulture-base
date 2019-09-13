#!/bin/sh


if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

if [ -e /dev/ada0 ]; then
  DISKSLICE=ada
else
  DISKSLICE=da
fi

echo $1 > /root/.tmpkey
geli setkey -J /root/.tmpkey /dev/${DISKSLICE}0p3
rm -f /root/.tmpkey

geli backup /dev/da0p3 /var/backups/${DISKSLICE}0p3.eli



