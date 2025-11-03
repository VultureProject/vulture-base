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
cat << EOF > ${TARGET}/etc/hosts
127.0.0.1 localhost
::1 localhost
127.0.0.2 mongodb
fd00::202 mongodb
127.0.0.3 redis
fd00::203 redis
127.0.0.4 rsyslog
fd00::204 rsyslog
127.0.0.5 haproxy
fd00::205 haproxy
127.0.0.6 apache
fd00::206 apache
127.0.0.7 portal
fd00::207 portal
EOF

# Host's dnsmasq resolver is used by jails -> local loopback of the jail
case "$JAIL_NAME" in
    mongodb)
        /bin/echo "nameserver 127.0.0.2" > ${TARGET}/etc/resolv.conf
        ;;
    redis)
        /bin/echo "nameserver 127.0.0.3" > ${TARGET}/etc/resolv.conf
        ;;
    rsyslog)
        /bin/echo "nameserver 127.0.0.4" > ${TARGET}/etc/resolv.conf
        ;;
    haproxy)
        /bin/echo "nameserver 127.0.0.5" > ${TARGET}/etc/resolv.conf
        ;;
    apache)
        /bin/echo "nameserver 127.0.0.6" > ${TARGET}/etc/resolv.conf
        ;;
    portal)
        /bin/echo "nameserver 127.0.0.7" > ${TARGET}/etc/resolv.conf
        ;;
    *)
        ;;
esac
