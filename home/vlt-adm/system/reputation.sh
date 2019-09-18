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

wget https://predator.vultureproject.org/ipsets/firehol_level1.netset.gz -O /tmp/firehol_level1.netset.gz 2> /dev/null
wget https://predator.vultureproject.org/ipsets/tor-exit.netset.gz -O /tmp/tor-exit.netset.gz 2> /dev/null
wget https://predator.vultureproject.org/ipsets/webscanner.netset.gz -O /tmp/webscanner.netset.gz 2> /dev/null
wget https://predator.vultureproject.org/ipsets/vulture-v4.netset -O /tmp/vulture-v4.netset 2> /dev/null
wget https://predator.vultureproject.org/ipsets/vulture-v6.netset -O /tmp/vulture-v6.netset 2> /dev/null

gunzip /tmp/firehol_level1.netset.gz
gunzip /tmp/tor-exit.netset.gz
gunzip /tmp/webscanner.netset.gz

mv /tmp/*.netset /var/db/darwin/