#!/bin/sh

#This script automatically create an IP management address
/usr/bin/touch /usr/local/etc/management.ip
/usr/sbin/chown root:wheel /usr/local/etc/management.ip
/bin/chmod 644 /usr/local/etc/management.ip
ip="$(/sbin/ifconfig | /usr/bin/grep inet | /usr/bin/grep -v '127.0.0.1' \
      | /usr/bin/grep -v ' ::1 ' | /usr/bin/grep -v 'fd00::20' | /usr/bin/grep -v 'fe80:' \
      | /usr/bin/awk '{print $2}' | /usr/bin/awk -vRS="" -vOFS=' ' '$1=$1')"
/bin/echo "$ip" | /usr/bin/sed -e 's/ .*//' > /usr/local/etc/management.ip
