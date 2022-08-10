#!/bin/sh

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

/usr/bin/printf "$1" > /etc/rc.conf.d/network
/bin/echo 'ifconfig_lo0="inet 127.0.0.1 netmask 255.255.255.0"' >> /etc/rc.conf.d/network
/bin/echo 'ifconfig_lo0_ipv6="inet6 ::1 prefixlen 128"' >> /etc/rc.conf.d/network
/bin/echo 'ifconfig_lo0_alias0="inet6 fd00::201 prefixlen 128"' >> /etc/rc.conf.d/network
/bin/echo 'cloned_interfaces="lo1 lo2 lo3 lo4 lo5 lo6"' >> /etc/rc.conf.d/network

/usr/sbin/service netif restart
