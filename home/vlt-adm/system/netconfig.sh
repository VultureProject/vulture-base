#!/bin/sh

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

# In case of automatic needs, export env variable AUTO=yes
if [ "$AUTO" != "yes" ] ; then
    /usr/sbin/bsdinstall netconfig
fi
if [ -f /tmp/bsdinstall_etc/rc.conf.net ]; then
    /usr/bin/xargs /usr/sbin/sysrc < /tmp/bsdinstall_etc/rc.conf.net

    # Set Vulture-specific static network configuration
    /usr/sbin/sysrc -f /etc/rc.conf.d/network ifconfig_lo0="inet 127.0.0.1 netmask 255.255.255.0"
    /usr/sbin/sysrc -f /etc/rc.conf.d/network ifconfig_lo0_ipv6="inet6 ::1 prefixlen 128"
    /usr/sbin/sysrc -f /etc/rc.conf.d/network ifconfig_lo0_alias0="inet6 fd00::201 prefixlen 128"
    /usr/sbin/sysrc -f /etc/rc.conf.d/network cloned_interfaces="lo1 lo2 lo3 lo4 lo5 lo6"

    /usr/sbin/service netif restart
    dhcp_list=$(/usr/sbin/sysrc -ae | /usr/bin/grep -i "ifconfig.*dhcp" | /usr/bin/sed -e 's/.*_\(.*\)=\(.*\)/\1/' | sort -u)
    for i in ${dhcp_list}; do
         /sbin/dhclient "${i}"
    done

    # Restart routes
    /usr/sbin/service routing restart

    # Restart jails to re-apply ip addresses config
    /usr/sbin/service jail restart
fi
if [ -f /tmp/bsdinstall_etc/resolv.conf ]; then
    /bin/mv /tmp/bsdinstall_etc/resolv.conf /etc/
fi

/usr/local/bin/pfctl-get_management.sh
/usr/local/bin/pfctl-init.sh
/sbin/pfctl -f /usr/local/etc/pf.conf
