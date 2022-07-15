#!/bin/sh

#set -x  # -e exit on non return 0 command, -x is debug mode

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

JAIL="redis"
TARGET="/zroot/redis"
BASE="https://ci-01.nyi.hardenedbsd.org/pub/hardenedbsd/12-stable/amd64/amd64/BUILD-LATEST/base.txz"
SHA256="$(/usr/local/bin/curl -s -XGET https://ci-01.nyi.hardenedbsd.org/pub/hardenedbsd/12-stable/amd64/amd64/BUILD-LATEST/CHECKSUMS.SHA256 | /usr/bin/grep base.txz | /usr/bin/awk '{print $4}')"

if [ -f /etc/rc.conf.proxy ]; then
    . /etc/rc.conf.proxy
    export http_proxy=${http_proxy}
    export https_proxy=${https_proxy}
    export ftp_proxy=${ftp_proxy}
fi

# Retrieve management IP address
ip="$(/usr/sbin/sysrc -f /etc/rc.conf.d/network -n management_ip 2> /dev/null)"
# Ip no management IP - exit
if [ -z "$ip" ] ; then
    /bin/echo "Management IP address is null - please select 'Management' and retry." >> /dev/stderr
    exit 1
fi

# If the file already exists
# And does not have correct shasum - redownload-it
if [ -f /var/cache/pkg/base.txz ] && \
   [ "$(/sbin/sha256 -q /var/cache/pkg/base.txz | /usr/bin/sed -e 's/ .*//g')" != "${SHA256}" ]; then
    /bin/rm -f /var/cache/pkg/base.txz
fi

if [ ! -f /var/cache/pkg/base.txz ]; then
	/bin/echo -n "Downloading base.txz... "
	wget -O /var/cache/pkg/base.txz ${BASE} || (/bin/echo "Fail !" ; exit 1)
	/bin/echo "Ok!"
fi

/bin/echo -n "Verifying SHASUM for base.txz... "
if [ "$(/sbin/sha256 -q /var/cache/pkg/base.txz | /usr/bin/sed -e 's/ .*//g')" != "${SHA256}" ]; then
	/bin/echo "Bad shasum for base.txz"
	exit
else
	/bin/echo "Ok!"
fi

/bin/echo -n "Creating jail configuration... "
/usr/bin/touch /etc/jail.conf
/usr/bin/grep ${JAIL} /etc/jail.conf > /dev/null
if [ "$?" == "0" ]; then
	/bin/echo "Warning, jail configuration for ${JAIL} already exists !"
else
	/bin/cat /home/jails.redis/config/redis-jail.conf >> /etc/jail.conf
	/bin/echo "Ok!"
fi

# If $TARGET not mounted as zfs - create it
if [ "$(/sbin/zfs get mountpoint | /usr/bin/grep ${TARGET})" == "" ] ; then
    /sbin/zfs create -o atime=off -o mountpoint=${TARGET} zroot/${JAIL}
    /bin/echo "Ok!"
fi

# If base.txz has not been decompressed
if [ ! -f "${TARGET}/etc/hosts" ] ; then
    /bin/echo -n "Decompressing base system to jail..."
    /usr/bin/tar xf /var/cache/pkg/base.txz -C ${TARGET}
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
for service in "redis" "sentinel" ; do
    file="${TARGET}/etc/rc.conf.d/$service"
    option="${service}_enable"
    if [ "$(/usr/bin/grep "$option" "$file" 2> /dev/null)" == "" ]  ; then
        /bin/echo "$option=\"YES\"" >> "$file"
    else
        /usr/bin/sed -i '' 's/'$option'=.*/'$option'="YES"/g' "$file"
    fi
    option="${service}_config"
    if [ "$(/usr/bin/grep "$option" "$file" 2> /dev/null)" == "" ]  ; then
        /bin/echo "$option=\"/usr/local/etc/redis/${service}.conf\"" >> "$file"
    else
        /usr/bin/sed -i '' 's/'$option'=.*/'$option'="\/usr\/local\/etc\/redis\/'$service'.conf"/g' "$file"
    fi
done

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
/usr/sbin/pkg -j ${JAIL} install -y redis  || (echo "Fail !" ; exit 1)
/usr/sbin/pkg -j ${JAIL} install -y secadm secadm-kmod  || (echo "Fail !" ; exit 1)
/bin/echo "Ok !"

/bin/mkdir -p ${TARGET}/usr/local/etc/redis
/bin/mkdir -p ${TARGET}/var/sockets/redis/

/bin/mkdir -p ${TARGET}/var/db/vulture-redis/
chown redis:redis ${TARGET}/var/db/vulture-redis/
chmod 750 ${TARGET}/var/db/vulture-redis/

/bin/mkdir -p ${TARGET}/var/run/redis/
chown redis:redis ${TARGET}/var/run/redis/
chmod 750 ${TARGET}/var/run/redis/

/bin/cat /usr/local/etc/redis/templates/redis.tpl | /usr/bin/sed "s/{{ management_ip }}/${ip}/" > /usr/local/etc/redis/redis.conf
/bin/cat /usr/local/etc/redis/templates/sentinel.tpl | /usr/bin/sed "s/{{ management_ip }}/${ip}/" > /usr/local/etc/redis/sentinel.conf
/usr/sbin/chown -R redis:vlt-conf /usr/local/etc/redis/

/usr/bin/touch ${TARGET}/var/log/redis.log
/usr/sbin/chown root:redis ${TARGET}/var/log/redis.log
/bin/chmod 660 ${TARGET}/var/log/redis.log

/usr/bin/touch ${TARGET}/var/log/sentinel.log
/usr/sbin/chown root:redis ${TARGET}/var/log/sentinel.log
/bin/chmod 660 ${TARGET}/var/log/sentinel.log

# If /etcfstab already modified or mount already done
file="/etc/fstab"
for mount_path in "/var/sockets/redis ${TARGET}/var/sockets/redis" \
"/usr/local/etc/redis ${TARGET}/usr/local/etc/redis" ; do
    if [ "$(/usr/bin/grep "$mount_path" "$file" 2> /dev/null)" == "" ]  ; then
        /bin/echo "$mount_path nullfs   rw,late      0       0" >> "$file"
    fi
    if [ "$(/sbin/mount -p | /usr/bin/sed -E 's/[[:cntrl:]]+/ /g' | /usr/bin/grep "$mount_path")" == "" ] ; then
        /sbin/mount_nullfs -o rw,late $mount_path
    fi
done

/usr/sbin/jexec redis /usr/sbin/service redis start > /dev/null
/usr/sbin/jexec redis /usr/sbin/service sentinel start > /dev/null

#Cleanup
rm -f /zroot/*/var/cache/pkg/*

#Crontab is not used - disable it
#Note: We can't disable it sooner in mkjail, otherwise jail won't start
#jexec ${JAIL} sysrc cron_enable=NO
