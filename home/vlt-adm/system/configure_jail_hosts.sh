#!/bin/sh


if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

if [ $# -ne 1 ] ; then
    echo "Usage: $0 <jail_name>"
    exit 1
fi

JAIL_NAME="$1"
TARGET="/zroot/${JAIL_NAME}"

# Configure /etc/hosts of jail
/bin/echo "127.0.0.1 localhost" > ${TARGET}/etc/hosts
/bin/echo "::1 localhost" >> ${TARGET}/etc/hosts

i=2
for jail in mongodb redis rsyslog haproxy apache portal; do
    /bin/echo "127.0.0.$i $jail" >> ${TARGET}/etc/hosts
    /bin/echo "fd00::20$i $jail" >> ${TARGET}/etc/hosts

    # Host's dnsmasq resolver is used by jails -> local loopback of the jail
    if [ "$jail" = "$JAIL_NAME" ]; then
        echo "nameserver 127.0.0.$i" > ${TARGET}/etc/resolv.conf
    fi
    i=$((i + 1))
done
