#!/bin/sh

#set -x  # -e exit on non return 0 command, -x is debug mode

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

JAIL="haproxy"
TARGET="/zroot/haproxy"
BASE="https://ci-01.nyi.hardenedbsd.org/pub/hardenedbsd/12-stable/amd64/amd64/BUILD-LATEST/base.txz"
SHA256="$(/usr/local/bin/curl -s -XGET https://ci-01.nyi.hardenedbsd.org/pub/hardenedbsd/12-stable/amd64/amd64/BUILD-LATEST/CHECKSUMS.SHA256 | /usr/bin/grep base.txz | /usr/bin/awk '{print $4}')"


if [ -f /etc/rc.conf.proxy ]; then
    . /etc/rc.conf.proxy
    export http_proxy=${http_proxy}
    export https_proxy=${https_proxy}
    export ftp_proxy=${ftp_proxy}
fi

# If the file already exists
# And does not have correct shasum - redownload-it
if [ -f /var/cache/pkg/base.txz ] && \
   [ "$(/sbin/sha256 -q /var/cache/pkg/base.txz | /usr/bin/sed -e 's/ .*//g')" != "${SHA256}" ]; then
    /bin/rm -f /var/cache/pkg/base.txz
fi

if [ ! -f /var/cache/pkg/base.txz ]; then
	/bin/echo -n "Downloading base.txz... "
	/usr/local/bin/wget --progress=dot:giga -O /var/cache/pkg/base.txz "${BASE}" || (/bin/echo "Fail !" ; exit 1)
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
	/bin/cat /home/jails.haproxy/config/haproxy-jail.tpl | /usr/bin/sed "s/{{ip_config}}/ip4.addr = \"lo4|127.0.0.5\/32\"; ip6.addr = \"lo4|fd00::205\";/" >> /etc/jail.conf
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
option="${JAIL}_enable"
file="${TARGET}/etc/rc.conf.d/$JAIL"
if [ "$(/usr/bin/grep "$option" "$file" 2> /dev/null)" == "" ]  ; then
    /bin/echo "$option=\"YES\"" >> "$file"
else
    /usr/bin/sed -i '' 's/'$option'=.*/'$option'="YES"/g' "$file"
fi
/bin/echo "Ok!"

# Start jail
/bin/echo -n "Starting jail..."
/usr/sbin/jail -cm "${JAIL}"
cp /etc/master.passwd ${TARGET}/etc/
jexec ${JAIL} /usr/sbin/pwd_mkdb -p /etc/master.passwd
/bin/echo "Ok!"

# No need to verify if already done
/usr/sbin/pkg -j ${JAIL} install -y jq libevent apr secadm secadm-kmod openssl e2fsprogs-libuuid curl libxml2 lmdb lua53 pcre libmaxminddb ssdeep yajl || (/bin/echo "Fail !" ; exit 1)

/bin/cp -r /home/jails.haproxy/.zfs-source/* ${TARGET}/

/bin/mkdir ${TARGET}/var/db/pki

/bin/mkdir -p /usr/local/etc/haproxy.d/templates
/usr/sbin/chown -R vlt-os:vlt-web /usr/local/etc/haproxy.d

/bin/mkdir -p /var/tmp/haproxy/
/usr/sbin/chown -R vlt-os:vlt-web /var/tmp/haproxy/
/usr/sbin/chown -R vlt-os:vlt-web ${TARGET}/var/tmp/haproxy/

/usr/sbin/chown root:wheel ${TARGET}/usr/local/etc/rc.d/haproxy
/bin/chmod 500 ${TARGET}/usr/local/etc/rc.d/haproxy
/usr/sbin/chown -R vlt-os:vlt-web ${TARGET}/usr/local/etc/haproxy.d

/bin/mkdir -p ${TARGET}/var/sockets/rsyslog
/bin/mkdir -p ${TARGET}/var/sockets/haproxy
/bin/mkdir -p ${TARGET}/home/darwin/spoa

/bin/mkdir -p ${TARGET}/var/sockets/darwin
/usr/sbin/chown -R darwin:vlt-web ${TARGET}/var/sockets/darwin
/bin/chmod 750 ${TARGET}/var/sockets/darwin

# If /etcfstab already modified or mount already done
file="/etc/fstab"
for mount_path in "/var/tmp/haproxy ${TARGET}/var/tmp/haproxy" \
"/var/db/pki ${TARGET}/var/db/pki" \
"/usr/local/etc/haproxy.d ${TARGET}/usr/local/etc/haproxy.d" \
"/var/sockets/rsyslog ${TARGET}/var/sockets/rsyslog" \
"/var/sockets/darwin ${TARGET}/var/sockets/darwin"; do
    if [ "$(/usr/bin/grep "$mount_path" "$file" 2> /dev/null)" == "" ]  ; then
        /bin/echo "$mount_path nullfs   ro,late      0       0" >> "$file"
    fi
    if [ "$(/sbin/mount -p | /usr/bin/sed -E 's/[[:cntrl:]]+/ /g' | /usr/bin/grep "$mount_path")" == "" ] ; then
        /sbin/mount_nullfs -o ro,late $mount_path
    fi
done

mount_path="/var/sockets/haproxy ${TARGET}/var/sockets/haproxy"
if [ "$(/usr/bin/grep "$mount_path" "$file" 2> /dev/null)" == "" ]  ; then
    /bin/echo "$mount_path nullfs   rw,late      0       0" >> "$file"
fi
if [ "$(/sbin/mount -p | /usr/bin/sed -E 's/[[:cntrl:]]+/ /g' | /usr/bin/grep "$mount_path")" == "" ] ; then
    /sbin/mount_nullfs -o rw,late $mount_path
fi

#Cleanup
rm -f /zroot/*/var/cache/pkg/*

#Crontab is not used - disable it
#Note: We can't disable it sooner in mkjail, otherwise jail won't start
#jexec ${JAIL} sysrc cron_enable=NO
