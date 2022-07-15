#!/bin/sh

#This script automatically create an IP management address
ip="$(/sbin/ifconfig | /usr/bin/grep inet | /usr/bin/grep -v '127.0.0.1' \
      | /usr/bin/grep -v ' ::1 ' | /usr/bin/grep -v 'fd00::20' | /usr/bin/grep -v 'fe80:' \
      | /usr/bin/awk '{print $2}' | /usr/bin/awk -vRS="" -vOFS=' ' '$1=$1')"
/usr/sbin/sysrc -f /etc/rc.conf.d/network management_ip="$(/bin/echo "$ip" | /usr/bin/sed -e 's/ .*//')"
