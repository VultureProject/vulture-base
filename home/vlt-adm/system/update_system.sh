#!/bin/sh


if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

if [ -f /etc/rc.conf.proxy ]; then
    . /etc/rc.conf.proxy
    export http_proxy=${http_proxy}
    export https_proxy=${https_proxy}
    export ftp_proxy=${ftp_proxy}
fi

/usr/sbin/pkg update
/usr/sbin/pkg upgrade -y
/usr/sbin/freebsd-update --not-running-from-cron fetch install > /dev/null

for a in $(/bin/ls /home/ | grep "jails"); do
    jail="$(/bin/echo "$a" | /usr/bin/sed 's/jails\.//')"
    /bin/echo "Updating JAIL $jail"
    /usr/sbin/pkg -j "$jail" update
    /usr/sbin/pkg -j "$jail" upgrade -y
    /usr/sbin/freebsd-update -b /home/${a} --not-running-from-cron fetch install > /dev/null
done
