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

# Get the vm_switch IP
if ! [ -f /usr/local/etc/vm_switch.ip ] ; then
    echo "File /usr/local/etc/vm_switch.ip not found. Using default 192.168.1.1 as resolver."
    echo "192.168.1.1" > /usr/local/etc/vm_switch.ip
else
    ip="$(/bin/cat /usr/local/etc/vm_switch.ip)"
fi

# If the ip is null - Set default 192.168.1.1
if [ -z "$ip" ] ; then
    echo "File /usr/local/etc/vm_switch.ip empty, using default 192.168.1.1 as resolver."
    ip="192.168.1.1"
fi

echo "nameserver $ip" > ${TARGET}/etc/resolv.conf
