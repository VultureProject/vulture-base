#!/bin/sh

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

# For some reason, vulture's logs will be chown root:wheel by logrotate if
# they don't exist before vultured can start and causes a migration crash
/usr/sbin/chown -R vlt-os:wheel /var/log/vulture/os/

sudo -u vlt-os /home/jails.apache/.zfs-source/home/vlt-os/bootstrap/django_migration.sh

# Prevent script return code to be != 0 if services already running
service tshark status || service tshark start

