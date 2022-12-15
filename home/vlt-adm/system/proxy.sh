#!/bin/sh

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

proxy="$1"

export http_proxy=http://${proxy}
export https_proxy=http://${proxy}
export ftp_proxy=http://${proxy}

if [ -n "${proxy}" ]; then
    /bin/echo "http_proxy=http://${proxy}" > /etc/rc.conf.proxy
    /bin/echo "https_proxy=http://${proxy}" >> /etc/rc.conf.proxy
    /bin/echo "ftp_proxy=http://${proxy}" >> /etc/rc.conf.proxy
    # Copy proxy conf to jails
    for dir in /zroot/*/etc/ ; do /bin/cp /etc/rc.conf.proxy "$dir" ; done
    # update pkg.conf file to force pkg to use proxy
    if /usr/bin/grep -q "^PKG_ENV" /usr/local/etc/pkg.conf; then
        sed -i '' "s+^PKG_ENV.*+PKG_ENV {http_proxy: http://${proxy}, https_proxy: http://${proxy}}+g" /usr/local/etc/pkg.conf
    else
        /bin/echo "" >> /usr/local/etc/pkg.conf
        /bin/echo "PKG_ENV {http_proxy: http://${proxy}, https_proxy: http://${proxy}}" >> /usr/local/etc/pkg.conf
    fi
else
    /bin/rm /etc/rc.conf.proxy
    # Remove proxy from jails
    /bin/rm /zroot/*/etc/rc.conf.proxy
    # update pkg.conf file to force pkg to use proxy
    sed -i '' 's+^PKG_ENV.*+PKG_ENV {}+g' /usr/local/etc/pkg.conf
fi