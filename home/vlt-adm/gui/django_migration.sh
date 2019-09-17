#!/bin/sh

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

sudo -u vlt-os /home/jails.apache/.zfs-source/home/vlt-os/bootstrap/django_migration.sh

# Prevent script return code to be != 0 if services already running
service tshark status || service tshark start

