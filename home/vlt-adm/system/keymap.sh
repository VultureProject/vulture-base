#!/bin/sh


if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

if [ $# -ge 1 ]; then
    /bin/echo "keymap=\"$1\"" > /etc/rc.conf.keymap
    /usr/sbin/kbdmap -r 2> /dev/null
    sysrc kdbmap=$1
else
    /usr/sbin/bsdinstall keymap
    if [ -f /tmp/bsdinstall_etc/rc.conf.keymap ]; then
        /bin/cat /tmp/bsdinstall_etc/rc.conf.keymap | tr -d '"' > /etc/rc.conf.keymap
        /usr/sbin/kbdmap -r 2> /dev/null

        sysrc -f /etc/rc.conf $(cat /etc/rc.conf.keymap)
    fi
fi