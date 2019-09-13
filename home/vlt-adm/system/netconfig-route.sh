#!/bin/sh

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

/usr/bin/printf "$1" > /etc/rc.conf.d/routing
/usr/sbin/service routing restart
