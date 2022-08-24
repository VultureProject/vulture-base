#!/bin/sh

#This script automatically create an IP management address
management_ip="$(/sbin/ifconfig | /usr/bin/grep inet | /usr/bin/grep -v '127.0.0.1' \
      | /usr/bin/grep -v ' ::1 ' | /usr/bin/grep -v 'fd00::20' | /usr/bin/grep -v 'fe80:' \
      | /usr/bin/awk '{print $2}' | /usr/bin/awk -vRS="" -vOFS=' ' '$1=$1' | /usr/bin/sed -e 's/ .*//')"
# Ip no management IP - exit
if [ -z "$management_ip" ] ; then
      /bin/echo "Management IP address is null - please select 'Management' and retry." >> /dev/stderr
      exit 1
fi
/usr/sbin/sysrc -f /etc/rc.conf.d/network management_ip="$(/bin/echo "$management_ip")"
