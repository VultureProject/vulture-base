#!/bin/sh

#set -x  # -e exit on non return 0 command, -x is debug mode

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

JAIL="apache"
TARGET="/zroot/apache"


if [ -f /etc/rc.conf.proxy ]; then
    . /etc/rc.conf.proxy
    export http_proxy=${http_proxy}
    export https_proxy=${https_proxy}
    export ftp_proxy=${ftp_proxy}
fi

/bin/echo -n "Creating jail configuration... "
/usr/bin/touch /etc/jail.conf
/usr/bin/grep ${JAIL} /etc/jail.conf > /dev/null
if [ "$?" == "0" ]; then
	/bin/echo "Warning, jail configuration for ${JAIL} already exists !"
else
	/bin/cat /home/jails.apache/config/apache-jail.tpl >> /etc/jail.conf
	/bin/echo "Ok!"
fi

# If $TARGET not mounted as zfs - create it
if [ "$(/sbin/zfs get mountpoint | /usr/bin/grep ${TARGET})" == "" ] ; then
    /sbin/zfs create -o atime=off -o mountpoint=${TARGET} zroot/${JAIL}
    /bin/echo "Ok!"
fi

# Create/decompress base system if not already done
if [ ! -f "${TARGET}/etc/hosts" ] ; then
    /bin/echo "Decompressing base system to jail..."
    /bin/mkdir -p /tmp/update
    # -i ignore version check (always install)
    # -n do not update kernel (useless for jail)
    # -d do not use DNSSEC
    # -D do not download update (allows to reuse update from local directory if it already exists)
    # -T keep downloaded update (allow reuse)
    # -t specify download directory
    if ! /usr/sbin/hbsd-update -indDTt /tmp/update -r ${TARGET} > /dev/null ; then
        /bin/echo "Cache folder doesn't exist yet, downloading and installing..."
        /usr/sbin/hbsd-update -indTt /tmp/update -r ${TARGET} > /dev/null
    fi
    /bin/echo "Ok!"
fi

/bin/echo "Copying required config files to jail..."
/home/vlt-adm/system/configure_jail_hosts.sh "$JAIL"

for i in /etc/passwd /etc/group; do
    /bin/echo "   -> ${i}"
    /bin/cp ${i} ${TARGET}/etc/
done

file="${TARGET}/etc/rc.conf"
for option in "syslogd_enable" "sendmail_enable" "sendmail_submit_enable" \
              "sendmail_outbound_enable" "sendmail_msp_queue_enable" ; do
    if [ "$(/usr/bin/grep "$option" "$file" 2> /dev/null)" == "" ]  ; then
        /bin/echo "$option=\"NO\"" >> "$file"
    else
        /usr/bin/sed -i '' 's/'$option'=.*/'$option'="NO"/g' "$file"
    fi
done

/bin/echo 'gunicorn_enable="YES"' > ${TARGET}/etc/rc.conf.d/gunicorn
/bin/echo 'nginx_enable="YES"' > ${TARGET}/etc/rc.conf.d/nginx

/bin/echo "Ok!"

/bin/echo -n "Updating pkg repositories..."
/bin/cp /var/db/pkg/repo-HardenedBSD.sqlite ${TARGET}/var/db/pkg/
/bin/echo "Ok !"

# Start jail
/bin/echo -n "Starting jail..."
/usr/sbin/jail -cm "${JAIL}"
cp /etc/master.passwd ${TARGET}/etc/
jexec ${JAIL} /usr/sbin/pwd_mkdb -p /etc/master.passwd
/bin/echo "Ok!"

# No need to verify if already done
/bin/echo "Installing packages into jail... Please be patient"

/usr/sbin/pkg -j ${JAIL} install -y openssl || (/bin/echo "Fail !" ; exit 1)
/usr/sbin/pkg -j ${JAIL} install -y wget || (/bin/echo "Fail !" ; exit 1)
/usr/sbin/pkg -j ${JAIL} install -y nginx || (/bin/echo "Fail !" ; exit 1)
/usr/sbin/pkg -j ${JAIL} install -y acme.sh || (/bin/echo "Fail !" ; exit 1)
/usr/sbin/pkg -j ${JAIL} install -y openldap24-client || (/bin/echo "Fail !" ; exit 1)
/usr/sbin/pkg -j ${JAIL} install -y krb5 || (/bin/echo "Fail !" ; exit 1)
/usr/sbin/pkg -j ${JAIL} install -y radiusclient || (/bin/echo "Fail !" ; exit 1)
/usr/sbin/pkg -j ${JAIL} install -y node || (/bin/echo "Fail !" ; exit 1)
/usr/sbin/pkg -j ${JAIL} install -y libucl || (/bin/echo "Fail !" ; exit 1)
/usr/sbin/pkg -j ${JAIL} install -y secadm secadm-kmod || (/bin/echo "Fail !" ; exit 1)
/usr/sbin/pkg -j ${JAIL} install -y liblognorm || (/bin/echo "Fail !" ; exit 1)
/usr/sbin/pkg -j ${JAIL} install -y lang/python || (/bin/echo "Fail !" ; exit 1)

# Needed dependency for haproxy package copied from vulture-haproxy
/usr/sbin/pkg -j ${JAIL} install -y pcre2 || (/bin/echo "Fail !" ; exit 1)
/bin/echo "Ok !"

# Copy needed files from vulture-haproxy package to apache jail
mkdir -p /zroot/apache/usr/local/sbin
mkdir -p /zroot/apache/usr/local/lib
/bin/cp -Rpf /home/jails.haproxy/.zfs-source/usr/local/sbin/haproxy /zroot/apache/usr/local/sbin/haproxy
/bin/cp -Rpf /home/jails.haproxy/.zfs-source/usr/local/lib/libslz.* /zroot/apache/usr/local/lib/


# Jail NEEDS to be modified after system file modification !!!
/bin/echo -n "Syncing jail..."
/usr/sbin/jail -m "${JAIL}"
/bin/echo "Ok!"

cp -rf /home/jails.apache/.zfs-source/usr/local/etc/* "${TARGET}/usr/local/etc/"
/bin/mkdir ${TARGET}/var/db/pki

#Map Vulture-GUI to the HOST
rm -rf /home/vlt-os/env
ln -s /home/jails.apache/.zfs-source/home/vlt-os/env/ /home/vlt-os/env
ln -s /home/jails.apache/.zfs-source/home/vlt-os/vulture_os/ /home/vlt-os/vulture_os
ln -s /home/jails.apache/.zfs-source/home/vlt-os/scripts/ /home/vlt-os/scripts

touch /home/vlt-os/vulture_os/vulture_os/secret_key.py

# Map Vulture-GUI to the Apache JAIL (done via fstab below)
mkdir -p "${TARGET}/home/vlt-os"

chmod 750 /home/vlt-os/scripts/*
chmod 755 /home/vlt-os/env
chmod 755 /home/vlt-os/vulture_os
chown vlt-os:wheel /home/vlt-os/vulture_os/vulture_os/secret_key.py
chmod 600 /home/vlt-os/vulture_os/vulture_os/secret_key.py

/bin/mkdir -p /var/log/vulture/os/
/usr/sbin/chown vlt-os:wheel /var/log/vulture/os/
chmod 755 /var/log/vulture/os/

jexec ${JAIL} /bin/mkdir -p /var/log/vulture/os/
jexec ${JAIL} /bin/mkdir -p /var/log/vulture/portal/
jexec ${JAIL} chown -R vlt-os:vlt-web /var/log/vulture/
jexec ${JAIL} chmod -R 664 /var/log/vulture/*
jexec ${JAIL} find /var/log/vulture -type d -exec chmod 775 {} \;

# HAProxy conf files
/bin/mkdir -p ${TARGET}/usr/local/etc/haproxy.d
/usr/sbin/chown -R vlt-os:vlt-web ${TARGET}/usr/local/etc/haproxy.d

# Test conf HAProxy
jexec ${JAIL} /bin/mkdir -p /var/tmp/haproxy
jexec ${JAIL} chown vlt-os:vlt-web /var/tmp/haproxy
jexec ${JAIL} chmod 755 /var/tmp/haproxy

# Darwin conf files
/bin/mkdir -p ${TARGET}/home/darwin/conf
/usr/sbin/chown -R vlt-os:vlt-web ${TARGET}/home/darwin/conf

# Sockets
/bin/mkdir -p ${TARGET}/var/sockets/redis/
/bin/mkdir -p ${TARGET}/var/sockets/daemon/

/bin/echo "Ok !"

# If /etc/fstab already modified or mount already done
file="/etc/fstab"
for mount_path in "/var/db/pki ${TARGET}/var/db/pki" \
"/home/jails.apache/.zfs-source/home/vlt-os ${TARGET}/home/vlt-os" \
"/usr/local/etc/haproxy.d ${TARGET}/usr/local/etc/haproxy.d" \
"/home/darwin/conf ${TARGET}/home/darwin/conf" \
"/var/sockets/redis ${TARGET}/var/sockets/redis" \
"/var/sockets/daemon ${TARGET}/var/sockets/daemon"; do
    if [ "$(/usr/bin/grep "$mount_path" "$file" 2> /dev/null)" == "" ]  ; then
        /bin/echo "$mount_path nullfs   ro,late      0       0" >> "$file"
    fi
    if [ "$(/sbin/mount -p | /usr/bin/sed -E 's/[[:cntrl:]]+/ /g' | /usr/bin/grep "$mount_path")" == "" ] ; then
        /sbin/mount_nullfs -o ro,late $mount_path
    fi
done

# Mounting gui socket as rw
mount_path="/var/sockets/gui /zroot/apache/var/sockets/gui"
if [ "$(/usr/bin/grep "$mount_path" "/etc/fstab" 2> /dev/null)" == "" ]  ; then
    /bin/echo "$mount_path nullfs   rw,late      0       0" >> "/etc/fstab"
fi
if [ "$(/sbin/mount -p | /usr/bin/sed -E 's/[[:cntrl:]]+/ /g' | /usr/bin/grep "$mount_path")" == "" ] ; then
    /sbin/mount_nullfs -o rw,late $mount_path
fi

#Cleanup
rm -f /zroot/*/var/cache/pkg/*

# Enabling secadm
jexec ${JAIL} sysrc secadm_enable=YES
jexec ${JAIL} service secadm start

#Crontab is not used - disable it
#Note: We can't disable it sooner in mkjail, otherwise jail won't start
#jexec ${JAIL} sysrc cron_enable=NO
