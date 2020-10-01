#!/bin/sh


if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

ip="$1"

/sbin/ifconfig | grep "$ip" > /dev/null
if [ "$?" == 0 ]; then
    /bin/echo "$ip" > /usr/local/etc/masquerading.ip

    /usr/local/bin/pfctl-init.sh
    /sbin/pfctl -f /usr/local/etc/pf.conf

else
    /bin/echo "Invalid IP Address !"
fi
