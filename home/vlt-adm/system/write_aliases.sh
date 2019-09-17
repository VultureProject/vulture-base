#!/bin/sh

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

grep "^root:" /etc/mail/aliases > /dev/null
if [ "$?" == "1" ];then
    echo "root: ${1}" >> /etc/mail/aliases
else
    sed -i '' -E "s/^root:.*/root: ${1}/" /etc/mail/aliases
fi

grep "^vlt-adm:" /etc/mail/aliases > /dev/null
if [ "$?" == "1" ];then
    echo "vlt-adm: ${1}" >> /etc/mail/aliases
else
    sed -i '' -E "s/^vlt-adm:.*/vlt-adm: ${1}/" /etc/mail/aliases
fi

grep "^vlt-os:" /etc/mail/aliases > /dev/null
if [ "$?" == "1" ];then
    echo "vlt-os: ${1}" >> /etc/mail/aliases
else
    sed -i '' -E "s/^vlt-os:.*/vlt-os: ${1}/" /etc/mail/aliases
fi

grep "^netdata:" /etc/mail/aliases > /dev/null
if [ "$?" == "1" ];then
    echo "netdata: ${1}" >> /etc/mail/aliases
else
    sed -i '' -E "s/^netdata:.*/netdata: ${1}/" /etc/mail/aliases
fi

/usr/bin/newaliases
postalias /etc/aliases