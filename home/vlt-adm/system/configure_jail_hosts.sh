#!/bin/sh


if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

if [ $# -ne 1 ] ; then
    echo "Usage: $0 <jail_name>"
    exit 1
fi

TARGET="/zroot/$1"

# Configure /etc/hosts of jail
/bin/echo "::1 localhost" > ${TARGET}/etc/hosts
/bin/echo "127.0.0.1 localhost" >> ${TARGET}/etc/hosts
/bin/echo "fd00::202 mongodb" >> ${TARGET}/etc/hosts
/bin/echo "127.0.0.2 mongodb" >> ${TARGET}/etc/hosts
/bin/echo "fd00::203 redis" >> ${TARGET}/etc/hosts
/bin/echo "127.0.0.3 redis" >> ${TARGET}/etc/hosts
/bin/echo "fd00::204 rsyslog" >> ${TARGET}/etc/hosts
/bin/echo "127.0.0.4 rsyslog" >> ${TARGET}/etc/hosts
/bin/echo "fd00::205 haproxy" >> ${TARGET}/etc/hosts
/bin/echo "127.0.0.5 haproxy" >> ${TARGET}/etc/hosts
/bin/echo "127.0.0.6 apache" >> ${TARGET}/etc/hosts
/bin/echo "fd00::206 apache" >> ${TARGET}/etc/hosts
/bin/echo "127.0.0.7 portal" >> ${TARGET}/etc/hosts
/bin/echo "fd00::207 portal" >> ${TARGET}/etc/hosts

# Host's dnsmasq resolver is used by jails
echo "nameserver 127.0.0.1" > ${TARGET}/etc/resolv.conf
