#!/bin/sh


if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

/bin/echo "$1" > /etc/rc.conf.ntp
/bin/echo "Updating time from $1 ... "
service ntpd stop 2> /dev/null
/usr/sbin/ntpdate "$1"

cat << EOF > /etc/ntp.conf
tos minclock 3 maxclock 6

server $1 iburst

restrict default limited kod nomodify notrap noquery nopeer
restrict source  limited kod nomodify notrap noquery

restrict 127.0.0.1
restrict ::1

leapfile "/var/db/ntpd.leap-seconds.list"
EOF


service ntpd start 2> /dev/null
