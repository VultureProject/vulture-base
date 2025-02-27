#!/bin/sh


if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

ip="$(/usr/sbin/sysrc -f /etc/rc.conf.d/network -n management_ip 2> /dev/null)"
. /etc/rc.conf

if ! grep "localhost" /etc/hosts 2>&1 > /dev/null; then
    /bin/echo "::1 localhost" >> /etc/hosts
    /bin/echo "127.0.0.1 localhost" >> /etc/hosts
fi
if ! grep "mongodb" /etc/hosts 2>&1 > /dev/null; then
    /bin/echo "fd00::202 mongodb" >> /etc/hosts
    /bin/echo "127.0.0.2 mongodb" >> /etc/hosts
fi

if ! grep "redis" /etc/hosts 2>&1 > /dev/null; then
    /bin/echo "fd00::203 redis" >> /etc/hosts
    /bin/echo "127.0.0.3 redis" >> /etc/hosts
fi

if ! grep "rsyslog" /etc/hosts 2>&1 > /dev/null; then
    /bin/echo "fd00::204 rsyslog" >> /etc/hosts
    /bin/echo "127.0.0.4 rsyslog" >> /etc/hosts
fi

if ! grep "haproxy" /etc/hosts 2>&1 > /dev/null; then
    /bin/echo "fd00::205 haproxy" >> /etc/hosts
    /bin/echo "127.0.0.5 haproxy" >> /etc/hosts
fi

if ! grep "apache" /etc/hosts 2>&1 > /dev/null; then
    /bin/echo "127.0.0.6 apache" >> /etc/hosts
    /bin/echo "fd00::206 apache" >> /etc/hosts
fi

if ! grep "portal" /etc/hosts 2>&1 > /dev/null; then
    /bin/echo "127.0.0.7 portal" >> /etc/hosts
    /bin/echo "fd00::207 portal" >> /etc/hosts
fi

# If ip already exists in the file, replace the line using ip as match
if grep -E "^${ip}[[:space:]]" /etc/hosts 2>&1 > /dev/null; then
    /usr/bin/sed -i '' "/^${ip}[[:space:]]/c\\
${ip} ${hostname}
" /etc/hosts
# If hostname already exists in the file, replace the line using hostname as match
elif grep -E "[[:space:]]${hostname}$" /etc/hosts 2>&1 > /dev/null; then
    /usr/bin/sed -i '' "/[[:space:]]${hostname}$/c\\
${ip} ${hostname}
" /etc/hosts
else
    /bin/echo "${ip} ${hostname}" >> /etc/hosts
fi

#TODO deprecate file
/bin/echo "${hostname}" > /etc/host-hostname
if [ -f /home/vlt-os/vulture_os/vulture_os/.env ]; then
    /usr/sbin/sysrc -f /home/vlt-os/vulture_os/vulture_os/.env VULTURE_HOSTNAME="${hostname}"
fi
if [ -f /home/vlt-os/vulture_os/portal/.env ]; then
    /usr/sbin/sysrc -f /home/vlt-os/vulture_os/portal/.env VULTURE_HOSTNAME="${hostname}"
fi

# Set hostname=127.0.0.2 into MongoDB jail - it can then resolve himself
/bin/cp /etc/hosts /zroot/mongodb/etc/hosts
/usr/bin/sed -i '' "s/$ip/127.0.0.2/" /zroot/mongodb/etc/hosts

#Copy hosts file to jails
for jail in apache mongodb redis rsyslog haproxy portal; do
    #TODO deprecate file
    /bin/echo "${hostname}" > /zroot/${jail}/etc/host-hostname
    /bin/echo "nameserver ${jail}" > /zroot/${jail}/etc/resolv.conf
done

# Reload dnsmasq service to account for potential changes in /etc/hosts
/usr/sbin/service dnsmasq reload
