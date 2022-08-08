#!/bin/sh


if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

ip="$(/bin/cat /usr/local/etc/management.ip)"
. /etc/rc.conf

/bin/echo "::1 localhost" > /etc/hosts
/bin/echo "127.0.0.1 localhost" >> /etc/hosts

/bin/echo "fd00::202 mongodb" >> /etc/hosts
/bin/echo "127.0.0.2 mongodb" >> /etc/hosts

/bin/echo "fd00::203 redis" >> /etc/hosts
/bin/echo "127.0.0.3 redis" >> /etc/hosts

/bin/echo "fd00::204 rsyslog" >> /etc/hosts
/bin/echo "127.0.0.4 rsyslog" >> /etc/hosts

/bin/echo "fd00::205 haproxy" >> /etc/hosts
/bin/echo "127.0.0.5 haproxy" >> /etc/hosts

/bin/echo "127.0.0.6 apache" >> /etc/hosts
/bin/echo "fd00::206 apache" >> /etc/hosts

/bin/echo "127.0.0.7 portal" >> /etc/hosts
/bin/echo "fd00::207 portal" >> /etc/hosts


/bin/echo "${ip} ${hostname}" >> /etc/hosts
/bin/echo "${hostname}" > /etc/host-hostname

# Set hostname=127.0.0.2 into MongoDB jail - it can then resolve himself
/bin/cp /etc/hosts /zroot/mongodb/etc/hosts
/usr/bin/sed -i '' "s/$ip/127.0.0.2/" /zroot/mongodb/etc/hosts

#Copy hosts file to jails
for jail in apache mongodb redis rsyslog haproxy portal; do
    /bin/cp /usr/local/etc/management.ip /zroot/${jail}/usr/local/etc/management.ip
    /bin/echo "${hostname}" > /zroot/${jail}/etc/host-hostname
    /bin/echo "nameserver ${jail}" > /zroot/${jail}/etc/resolv.conf
done

# Reload dnsmasq service to account for potential changes in /etc/hosts
/usr/sbin/service dnsmasq reload
