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
    if ! ( /usr/bin/grep "ifconfig_lo0=" /tmp/bsdinstall_etc/rc.conf.net )
    then
        /bin/echo 'ifconfig_lo0="inet 127.0.0.1 netmask 255.255.255.0"' >> /tmp/bsdinstall_etc/rc.conf.net
    fi
    if ! ( /usr/bin/grep "ifconfig_lo0_ipv6=" /tmp/bsdinstall_etc/rc.conf.net )
    then
        /bin/echo 'ifconfig_lo0_ipv6="inet6 ::1 prefixlen 128"' >> /tmp/bsdinstall_etc/rc.conf.net
        /bin/echo 'ifconfig_lo0_alias0="inet6 fd00::201 prefixlen 128"' >> /tmp/bsdinstall_etc/rc.conf.net
    fi
    if ! ( /usr/bin/grep "ifconfig_tap0=" /tmp/bsdinstall_etc/rc.conf.net )
    then
        /bin/echo 'ifconfig_tap0="inet 192.168.1.1 netmask 255.255.255.0"' >> /tmp/bsdinstall_etc/rc.conf.net
    fi
    /bin/cp /tmp/bsdinstall_etc/rc.conf.net /etc/rc.conf.d/network
    if ! ( /usr/bin/grep "cloned_interfaces=" /etc/rc.conf.d/network )
    then
        /bin/echo 'cloned_interfaces="lo1 lo2 lo3 lo4 lo5 lo6"' >> /etc/rc.conf.d/network
    fi

    /usr/sbin/service netif restart
    dhcp_list=$(/usr/bin/grep "SYNCDHCP" /etc/rc.conf.d/network | /usr/bin/sed -e 's/.*_\(.*\)="SYNCDHCP"/\1/')
    for i in ${dhcp_list}; do
         /sbin/dhclient ${i}
    done

    # Routes needs to be in a separate configuration file
    /usr/bin/grep route /etc/rc.conf.d/network > /etc/rc.conf.d/routing

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
