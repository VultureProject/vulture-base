#!/bin/sh

#set -x  # -e exit on non return 0 command, -x is debug mode

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

JAIL="rsyslog"
TARGET="/zroot/rsyslog"

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
	echo "Warning, jail configuration for ${JAIL} already exists !"
else
    management_ip=$(/usr/sbin/sysrc -f /etc/rc.conf.d/network -n management_ip 2> /dev/null)
    # Ip no management IP - exit
    if [ -z "$management_ip" ] ; then
        /bin/echo "Management IP address is null - please select 'Management' and retry." >> /dev/stderr
        exit 1
    fi
    # If IPv6
    if echo $management_ip | grep ":" > /dev/null 2>&1; then
        /bin/cat /home/jails.rsyslog/config/${JAIL}-jail.tpl | /usr/bin/sed "s/{{ip_config}}/ip6.addr += \"$management_ip\";/" >> /etc/jail.conf
    else
        /bin/cat /home/jails.rsyslog/config/${JAIL}-jail.tpl | /usr/bin/sed "s/{{ip_config}}/ip4.addr += \"$management_ip\";/" >> /etc/jail.conf
    fi
	echo "Ok!"
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

mkdir -p ${TARGET}/etc/rc.conf.d/
echo 'rsyslogd_enable="YES"' > ${TARGET}/etc/rc.conf.d/rsyslogd
echo 'rsyslogd_pidfile="/var/run/rsyslog.pid"' >> ${TARGET}/etc/rc.conf.d/rsyslogd
echo 'rsyslogd_config="/usr/local/etc/rsyslog.conf"' >> ${TARGET}/etc/rc.conf.d/rsyslogd
echo 'filebeat_enable="YES"' > ${TARGET}/etc/rc.conf.d/filebeat
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

/bin/cp -rf /home/jails.rsyslog/.zfs-source/* ${TARGET}

# No need to verify if already done
/bin/echo "Installing packages into jail... Please be patient"
/usr/sbin/pkg -j ${JAIL} install -y librelp libfastjson libinotify liblogging curl \
e2fsprogs-libuuid libmaxminddb hiredis openssl pcre icu cyrus-sasl libestr libgcrypt libxml2 liblz4 librdkafka libevent || (/bin/echo "Fail !" ; exit 1)
/usr/sbin/pkg -j ${JAIL} install -y secadm secadm-kmod
/bin/echo "Ok !"

#Security fix: We do not want the jail to have the curl command available (libcurl is needed by rsyslog)
/bin/rm -f ${JAIL}/usr/local/bin/curl

/bin/mkdir -p ${TARGET}/usr/local/etc/rsyslog.d
/bin/mkdir -p ${TARGET}/var/sockets/rsyslog/
/bin/mkdir -p ${TARGET}/var/sockets/darwin/
/bin/mkdir -p ${TARGET}/home/vlt-os/vulture_os/services/rsyslogd/config
/bin/mkdir -p ${TARGET}/var/db/pki
/bin/mkdir -p ${TARGET}/var/log/pf
/bin/mkdir -p ${TARGET}/var/db/darwin
/bin/mkdir -p ${TARGET}/var/log/darwin
/bin/mkdir -p ${TARGET}/var/log/api_parser
/bin/mkdir -p ${TARGET}/var/db/reputation_ctx
/bin/mkdir -p /usr/local/etc/rsyslog.d/
/bin/mkdir -p /var/sockets/rsyslog/

/bin/chmod 500 ${TARGET}/usr/local/etc/rc.d/rsyslogd
/usr/sbin/chown root:wheel ${TARGET}/usr/local/etc/rc.d/rsyslogd
/usr/sbin/chown vlt-os:wheel /usr/local/etc/rsyslog.d
/usr/sbin/chown -R vlt-os:vlt-web ${TARGET}/home/vlt-os/vulture_os/services/rsyslogd/config
/usr/sbin/chown -R root:wheel ${TARGET}/var/db/darwin
/bin/chmod -R 440 ${TARGET}/var/db/darwin
/usr/sbin/chown -R root:wheel ${TARGET}/var/log/darwin
/bin/chmod 550 ${TARGET}/var/log/darwin
/usr/sbin/chown -R root:wheel ${TARGET}/var/db/reputation_ctx
/bin/chmod -R 440 ${TARGET}/var/db/reputation_ctx

# If /etcfstab already modified or mount already done
file="/etc/fstab"
for mount_path in "/usr/local/etc/rsyslog.d ${TARGET}/usr/local/etc/rsyslog.d" \
"/var/db/pki ${TARGET}/var/db/pki" \
"/var/log/pf ${TARGET}/var/log/pf" \
"/var/log/api_parser ${TARGET}/var/log/api_parser" \
"/var/db/darwin ${TARGET}/var/db/darwin" \
"/var/sockets/darwin ${TARGET}/var/sockets/darwin" \
"/var/log/darwin ${TARGET}/var/log/darwin" \
"/var/db/reputation_ctx ${TARGET}/var/db/reputation_ctx" \
"/zroot/apache/home/vlt-os/vulture_os/services/rsyslogd/config ${TARGET}/home/vlt-os/vulture_os/services/rsyslogd/config" ; do
    if [ "$(/usr/bin/grep "$mount_path" "$file" 2> /dev/null)" == "" ]  ; then
        /bin/echo "$mount_path nullfs   ro,late      0       0" >> "$file"
    fi
    if [ "$(/sbin/mount -p | /usr/bin/sed -E 's/[[:cntrl:]]+/ /g' | /usr/bin/grep "$mount_path")" == "" ] ; then
        /sbin/mount_nullfs -o ro,late $mount_path
    fi
done

mount_path="/var/sockets/rsyslog ${TARGET}/var/sockets/rsyslog"
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
