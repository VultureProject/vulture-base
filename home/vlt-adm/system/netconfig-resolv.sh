#!/bin/sh

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

if [ "$1" ]; then
    /usr/bin/printf "%s" "$1" > /etc/resolv.conf
fi
