#!/bin/sh

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

proxy="$1"

export http_proxy=http://${proxy}
export https_proxy=http://${proxy}
export ftp_proxy=http://${proxy}

if [ "${proxy}" != "" ]; then
    /bin/echo "http_proxy=http://${proxy}" > /etc/rc.conf.proxy
    /bin/echo "https_proxy=http://${proxy}" >> /etc/rc.conf.proxy
    /bin/echo "ftp_proxy=http://${proxy}" >> /etc/rc.conf.proxy
else
    /bin/rm /etc/rc.conf.proxy
fi