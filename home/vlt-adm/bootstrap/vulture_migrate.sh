#!/bin/sh

SCRIPT=$(realpath "$0")

temp_dir="/var/tmp/update"

pkg_url="http://pkg.vultureproject.org/"
vulture_conf="Vulture.conf"
pkg_ca="pkg.vultureproject.org"
update_url="http://updates.vultureproject.org/"
vulture_update_conf="hbsd-update.conf"
vulture_update_ca="ca.vultureproject.org"
jail_path="/zroot"


update_repositories(){
    /bin/echo -n "[+] Updating repositories "
    # Usage update_repositories "prefix_dir"
    prefix_dir=""
    if [ -n "$1" ]; then
        prefix_dir="$1"
        /bin/echo " at $prefix_dir"
    else
        /bin/echo "on system"
    fi

    if [ ! -f ${temp_dir}/${vulture_conf} ]; then
        /bin/echo "[+] Downloading Vulture.conf"
        /usr/local/bin/wget ${pkg_url}${vulture_conf} --directory-prefix=${temp_dir} || finalize 1 "[/] Failed to download ${vulture_conf}"
        /bin/echo "[-] Done"
    fi

    /bin/echo "[+] Changing pkg repo to Vulture.conf"
    /bin/rm -f ${prefix_dir}/etc/pkg/*.conf ${prefix_dir}/usr/local/etc/pkg/repos/*.conf /var/db/etcupdate/old/etc/pkg/*.conf /var/db/etcupdate/current/etc/pkg/*.conf

    /bin/mkdir -p ${prefix_dir}/etc/pkg && /bin/cp ${temp_dir}/${vulture_conf} ${prefix_dir}/etc/pkg/${vulture_conf}
    /bin/mkdir -p ${prefix_dir}/usr/local/etc/pkg/repos && /bin/cp ${temp_dir}/${vulture_conf} ${prefix_dir}/usr/local/etc/pkg/repos/${vulture_conf}

    /bin/echo "[-] Done"

    if [ ! -f ${temp_dir}/${pkg_ca} ]; then
        /bin/echo "[+] Downloading $pkg_ca"
        /usr/local/bin/wget ${pkg_url}${pkg_ca} --directory-prefix=${temp_dir} || finalize 1 "[/] Failed to download $pkg_ca"
        /bin/echo "[-] Done"
    fi

    /bin/echo "[+] Saving $pkg_ca CA cert"
    /bin/rm -f  ${prefix_dir}/usr/share/keys/pkg/trusted/pkg.*
    /bin/mkdir -p ${prefix_dir}/usr/share/keys/pkg/trusted && /bin/cp ${temp_dir}/${pkg_ca}  ${prefix_dir}/usr/share/keys/pkg/trusted/${pkg_ca}
    /bin/echo "[-] Done"

    if [ ! -f ${temp_dir}/${vulture_update_conf} ]; then
        /bin/echo "[+] Downloading $vulture_update_conf"
        /usr/local/bin/wget ${update_url}${vulture_update_conf} --directory-prefix=${temp_dir} || finalize 1  "[/] Failed to download $vulture_update_conf"
        /bin/echo "[-] Done"
    fi

    /bin/echo "[+] Changing update repo to $vulture_update_conf"
    /bin/rm -f ${prefix_dir}/etc/hbsd-update.conf ${prefix_dir}/etc/hbsd-update.tor.conf
    /bin/mkdir -p ${prefix_dir}/etc && /bin/cp ${temp_dir}/${vulture_update_conf} ${prefix_dir}/etc/${vulture_update_conf}
    /bin/echo "[-] Done"

    if [ ! -f ${temp_dir}/${vulture_update_ca} ]; then
        /bin/echo "[+] Downloading $vulture_update_ca"
        /usr/local/bin/wget ${update_url}${vulture_update_ca} --directory-prefix=${temp_dir} || finalize 1  "[/] Failed to download $vulture_update_ca"
        /bin/echo "[-] Done"
    fi

    /bin/echo "[+] Saving $vulture_update_ca CA cert"
    /bin/rm -f ${prefix_dir}/usr/share/keys/hbsd-update/trusted/ca.hardenedbsd.org
    /bin/mkdir -p ${prefix_dir}/usr/share/keys/hbsd-update/trusted/ && /bin/cp ${temp_dir}/${vulture_update_ca} ${prefix_dir}/usr/share/keys/hbsd-update/trusted/${vulture_update_ca}
    /bin/echo "[-] Done"
}

download_system_update(){
    if [ ! -f ${temp_dir}/update.tar ]; then
        /bin/echo "[+] Downloading system update"
        /usr/sbin/hbsd-update -t "$temp_dir" -T -f || finalize 1  "[/] System update download failed"
        /bin/echo "[-] Done"
    fi
}

update_system(){
    # usage update_system [ jail basedir ]
    download_system_update
    options=""
    jail="$1"
    basedir="$2"
    /bin/echo -n "[+] Updating base system "
    if [ -n "$jail" ] ; then
        options="-j $jail"
        /bin/echo "of jail $jail"
    elif [ -n "$basedir" ] ; then
        options="-r $basedir"
        /bin/echo "at $basedir"
    else
        /bin/echo "of host"
    fi
    /usr/bin/yes "mf" | /usr/sbin/hbsd-update -d -t "$temp_dir" -T -D $options || finalize 1  "[/] System update failed"
    /bin/echo "[-] Done with update"
}


restart_system(){
    /bin/echo "[+] Setting up startup script"
    # enable script to be run on startup
    echo "@reboot root sleep 60 && /bin/sh $SCRIPT" > /etc/cron.d/vulture_update || finalize 1  "[/] Failed to setup startup script"
    /bin/echo "[+] Rebooting system"
    /sbin/shutdown -r now
}

update_packages(){
    echo "[+] Bootstrap pkg"
    IGNORE_OSVERSION="yes" /usr/sbin/pkg bootstrap -fy || finalize 1 "Could not bootstrap pkg"
    echo "[-] Done"
    echo "[+] Updating root pkg repository catalogue"
    IGNORE_OSVERSION="yes" /usr/sbin/pkg update -f || finalize 1 "Could not update list of packages"
    echo "[-] Done"
    echo "[+] Clear pkg cache before fetching"
    IGNORE_OSVERSION="yes" /usr/sbin/pkg clean -ya || finalize 1 "Could not clear pkg cache"
    echo "[-] Done clearing pkg cache"
    echo "[+] Fetching packages"
    # Fetch updated packages for root system
    IGNORE_OSVERSION="yes" /usr/sbin/pkg fetch -yu || finalize 1 "Failed to download packages"
    echo "[-] Done"

    /bin/echo "[+] Updating vulture-base"
    IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -fy vulture-base
    echo "[-] Done updating vulture-base !"

    /bin/echo "[+] Reloading dnsmasq..."
    # Ensure dnsmasq is up-to-date, as it could be modified during vulture-base upgrade
    /usr/sbin/service dnsmasq reload || /usr/sbin/service dnsmasq restart
    /bin/echo "[-] dnsmasq reloaded"

    for jail in "haproxy" "redis" "mongodb" "rsyslog" ; do
        /bin/echo "[+] Upgrading vulture-$jail..."
        IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -fy "vulture-$jail"
        case "$jail" in
            rsyslog)
                /usr/sbin/jexec "$jail" /usr/sbin/service rsyslogd restart
                ;;
            mongodb)
                /usr/sbin/jexec "$jail" /usr/sbin/service mongod restart
                # TODO Force disable pageexec and mprotect on the mongo executable
                # there seems to be a bug currently with secadm when rules are pre-loaded on executables in packages
                # which is the case for latest mongodb36-3.6.23
                /usr/sbin/jexec "$jail" /usr/sbin/hbsdcontrol pax disable pageexec /usr/local/bin/mongo
                /usr/sbin/jexec "$jail" /usr/sbin/hbsdcontrol pax disable mprotect /usr/local/bin/mongo
                ;;
            redis)
                /usr/sbin/jexec "$jail" /usr/sbin/service sentinel stop
                /usr/sbin/jexec "$jail" /usr/sbin/service redis restart
                /usr/sbin/jexec "$jail" /usr/sbin/service sentinel start
                ;;
            haproxy)
                # Stop gracefully
                /usr/sbin/jexec "$jail" /usr/sbin/service haproxy stop &
                # Wait for haproxy to stop
                /bin/sleep 5
                # Force stop if gracefull stop waiting
                /usr/sbin/jexec "$jail" /usr/sbin/service haproxy status && /usr/sbin/jexec "$jail" /usr/sbin/service haproxy hardstop
                # Then start
                /usr/sbin/jexec "$jail" /usr/sbin/service haproxy start
                ;;
            *)
                /usr/sbin/jexec "$jail" /usr/sbin/service "$jail" restart
                ;;
        esac
        /bin/echo "[-] Done upgrading vulture-$jail."
    done

    /usr/sbin/service darwin stop
    /bin/echo "[+] Updating darwin..."
    IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -fy darwin || finalize 1 "Failed to upgrade package Darwin"
    /bin/echo "[-] Darwin updated, starting service"
    /usr/sbin/service darwin start

    /bin/echo "[+] Upgrading GUI"
    /bin/echo "[+] Updating apache and portal jails' packages..."
    IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -fy vulture-gui
    /bin/echo "[+] Done upgrading GUI"

    /bin/echo "[+] Upgrading host system packages"
    IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -y -f
    /bin/echo "[-] Done"

    /bin/echo "[+] Reloading dnsmasq..."
    # Ensure dnsmasq is up-to-date, as it could be modified during vulture-gui upgrade
    /usr/sbin/service dnsmasq reload || /usr/sbin/service dnsmasq restart
    /bin/echo "[-] dnsmasq reloaded"

    # Load secadm module into kernel and start
    /bin/echo "[+] Upgrading updating secadm"
    IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -fy secadm secadm-kmod
    /bin/echo "[-] Done"
    kldload secadm

    # Do not start vultured if the node is not installed
    if /usr/local/bin/sudo -u vlt-os /home/vlt-os/env/bin/python /home/vlt-os/vulture_os/manage.py is_node_bootstrapped >/dev/null 2>&1 ; then
        /usr/sbin/service vultured restart
    fi

    /bin/echo "[+] Cleaning pkg cache..."
    /usr/sbin/pkg clean -ay
    /bin/echo "[-] Done."
}

verify_services(){
    # Vultured
    /bin/echo "[+] Checking if vultured is running..."
    if /usr/local/bin/sudo -u vlt-os /home/vlt-os/env/bin/python /home/vlt-os/vulture_os/manage.py is_node_bootstrapped >/dev/null 2>&1 ; then
        /usr/sbin/service vultured restart
    fi
    /bin/echo "[-] Done"

    # Apache
    /bin/echo "[+] [apache] Checking if nginx is running..."
    jexec apache service nginx status || jexec apache service nginx restart
    /bin/echo "[-] Done"
    /bin/echo "[+] [apache] Checking if gunicorn is running..."
    jexec apache service gunicorn status || jexec apache service gunicorn restart
    /bin/echo "[-] Done"
    # mongodb
    /bin/echo "[+] Checking if mongodb is running..."
    jexec mongodb service mongod status || jexec mongodb service mongod restart
    /bin/echo "[-] Done"

    # rsyslog
    /bin/echo "[+] Checking if rsyslog is running..."
    jexec rsyslog service rsyslogd status || jexec rsyslog service rsyslogd restart
    /bin/echo "[-] Done"

    # portal
    /bin/echo "[+] [portal] Checking if gunicorn is running..."
    jexec portal service gunicorn status || jexec portal service gunicorn restart
    /bin/echo "[-] Done"

    # redis
    /bin/echo "[+] [redis] Checking if sentinel is running..."
    jexec redis service sentinel status || jexec redis service sentinel restart
    /bin/echo "[-] Done"

    # the rest of the jails
    for jail in "haproxy" "redis" ; do
        /bin/echo "[+] Checking if $jail is running..."
        jexec "$jail" service "$jail" status || jexec "$jail" service "$jail" restart
        /bin/echo "[-] Done"
    done
}

finalize() {
    # set default in case err_code is not specified
    err_code=$1
    err_message=$2
    # does not work with '${1:=0}' if $1 is not set...
    err_code=${err_code:=0}


    if [ -n "$err_message" ]; then
        echo ""
        echo "[!] ${err_message}"
        echo ""
    fi

    echo "[+] Cleaning temporary dir..."
    /bin/rm -rf $temp_dir
    echo "[-] Done."

    # Re-enable secadm rules if on an HardenedBSD system
    echo "[+] Enabling root secadm rules"
    /usr/sbin/service secadm start || echo "Could not enable secadm rules"
    echo "[-] Done."

    for jail in "mongodb" "apache" "portal"; do
        echo "[+] [${jail}] Enabling secadm rules"
        /usr/sbin/jexec $jail /usr/sbin/service secadm start || echo "Could not enable secadm rules"
        echo "[-] Done."
    done

    # Be sure to restart dnsmasq: No side-effect and it deals with dnsmasq configuration changes
    /usr/sbin/service dnsmasq restart

    # remove script from running at start up
    rm -f /etc/cron.d/vulture_update

    exit $err_code
}

initialize() {
    if [ "$(/usr/bin/id -u)" != "0" ]; then
        /bin/echo "This script must be run as root" 1>&2
        exit 1
    fi

    trap finalize SIGINT

    if [ -f /etc/rc.conf.proxy ]; then
        . /etc/rc.conf.proxy
        export http_proxy=${http_proxy}
        export https_proxy=${https_proxy}
        export ftp_proxy=${ftp_proxy}
    fi

    log_file=/var/log/vulture_update.log
    echo "Output is sent to $log_file"

    exec 3>&1 4>&2
    trap 'exec 2>&4 1>&3' 0 1 2 3
    exec 1>>$log_file 2>&1

    # Create temporary directory if it does not exist
    /bin/mkdir -p $temp_dir || echo "Temp directory exists, keeping"

    # Disable secadm rules
    echo "[+] Disabling root secadm rules"
    /usr/sbin/service secadm stop || echo "Could not disable secadm rules"
    echo "[-] Done."

    for jail in "mongodb" "apache" "portal"; do
        echo "[+] [${jail}] Disabling secadm rules"
        /usr/sbin/jexec $jail /usr/sbin/service secadm stop || echo "Could not disable secadm rules"
        echo "[-] Done."
    done
}
stop_services(){
    # Vultured
    /bin/echo "[+] Stopping vultured..."
    if /usr/local/bin/sudo -u vlt-os /home/vlt-os/env/bin/python /home/vlt-os/vulture_os/manage.py is_node_bootstrapped >/dev/null 2>&1 ; then
        /usr/sbin/service vultured stop
    fi
    /bin/echo "[-] Done!"

    # Apache
    /bin/echo "[+] [apache] Stopping nginx..."
    jexec apache service nginx status || jexec apache service nginx restart
    /bin/echo "[-] Done"
    /bin/echo "[+] [apache] Stopping gunicorn..."
    jexec apache service gunicorn status || jexec apache service gunicorn restart
    /bin/echo "[-] Done"

    # mongodb
    /bin/echo "[+] Stopping mongodb..."
    jexec mongodb service mongod stop
    /bin/echo "[-] Done"

    # rsyslog
    /bin/echo "[+] Stopping rsyslog..."
    jexec rsyslog service rsyslogd stop
    /bin/echo "[-] Done"

    # portal
    /bin/echo "[+] [portal] Stopping gunicorn..."
    jexec portal service gunicorn stop
    /bin/echo "[-] Done"

    # the rest of the jails
    for jail in "haproxy" "redis" ; do
        /bin/echo "[+] Stopping $jail..."
        jexec "$jail" service "$jail" stop
        /bin/echo "[-] Done"
    done

    /bin/echo "[+] Stopping jails..."
    service jail stop
    # wait for all services to stop successfully
    sleep 10
    /bin/echo "[-] Done"
}

mk_jail_system(){

    /bin/echo "[+] Unmounting fstab..."
    /bin/cp /etc/fstab /etc/fstab.bak
    umount -a -F /etc/fstab
    /bin/echo "[-] Done unmounting fstab. Backup kept at /etc/fstab.bak"

    # directory for backup
    /bin/mkdir -p /var/jails/update

    for jail in "haproxy" "rsyslog" "redis" "mongodb" "portal" "apache"; do
        echo "[+] Reconstructing old jail $jail"

        if zpool list -o name| grep "zroot" > /dev/null; then
            zpool="zroot"
        elif zpool list -o name| grep "vulture" > /dev/null; then
            zpool="vulture"
        fi
        echo "[+] Destroying ${zpool}/$jail datasets"
        zfs set mountpoint=none ${zpool}/$jail
        # unmount one by one because it fails sometimes
        if [ "$jail" == "mongodb" ]; then
            zfs unmount -f ${zpool}/$jail/var/db
        fi
        zfs unmount -f ${zpool}/$jail/var/log
        zfs unmount -f ${zpool}/$jail/var
        zfs unmount -f ${zpool}/$jail
        # rename children to be kept (var/log, var/db), delete parent and change name back
        zfs rename -p ${zpool}/$jail/var/log ${zpool}/update/$jail/var/log
        if [ "$jail" == "mongodb" ]; then
            zfs rename -p ${zpool}/$jail/var/db ${zpool}/update/$jail/var/db
        fi
        zfs destroy -rfv "${zpool}/$jail" #|| finalize 1 "Error destroying ${zpool}/$jail dataset"
        zfs rename -p ${zpool}/update/$jail/var ${zpool}/$jail/var
        # mount on host so they are independent of jail
        if [ -d /var/jails/$jail ]; then
            /bin/echo "[+] Backing up /var/jails/$jail in /var/jails/update/$jail"
            /bin/mv /var/jails/$jail /var/jails/update/
        fi
        /bin/echo "[+] Mounting ${zpool}/$jail at /var/jails/$jail"
        zfs set mountpoint=/var/jails/$jail ${zpool}/$jail
        zfs set mountpoint=/var/jails/$jail/var ${zpool}/$jail/var
        zfs set mountpoint=/var/jails/$jail/var/log ${zpool}/$jail/var/log
        zfs mount ${zpool}/$jail
        zfs mount ${zpool}/$jail/var
        zfs mount ${zpool}/$jail/var/log
        if [ "$jail" == "mongodb" ]; then
            zfs set mountpoint=/var/jails/$jail/var/db ${zpool}/$jail/var/db
            zfs mount ${zpool}/$jail/var/db
        fi

        if [ -d /var/jails/update/$jail ]; then
            /bin/echo "[+] Restoring /var/jails/$jail from /var/jails/update/$jail"
            /bin/cp -R /var/jails/update/$jail/ /var/jails/$jail
        fi

        # wait for destruction of datasets
        sleep 10
        /bin/echo "[-] Done destroying zroot/$jail datasets"

        /bin/echo "[+] Creating bastille jail $jail"
        /bin/rmdir /zroot/$jail

        /home/vlt-adm/system/create_jail.sh "$jail"

        /bin/echo "[-] Done reconstructing old jail $jail"
    done

    rm -rf /var/jails/update

    zfs destroy -rfv ${zpool}/update


    /bin/echo "[+] Removing old mounts in fstab"
    file="/etc/fstab"
    for mount_path in "/var/db/pki /zroot/apache/var/db/pki" \
    "/home/jails.apache/.zfs-source/home/vlt-os /zroot/apache/home/vlt-os" \
    "/usr/local/etc/haproxy.d /zroot/apache/usr/local/etc/haproxy.d" \
    "/home/darwin/conf /zroot/apache/home/darwin/conf" \
    "/var/sockets/redis /zroot/apache/var/sockets/redis" \
    "/var/sockets/daemon /zroot/apache/var/sockets/daemon" \
    "/var/sockets/gui /zroot/apache/var/sockets/gui" \
    "/var/tmp/haproxy /zroot/haproxy/var/tmp/haproxy" \
    "/var/db/pki /zroot/haproxy/var/db/pki" \
    "/usr/local/etc/haproxy.d /zroot/haproxy/usr/local/etc/haproxy.d" \
    "/var/sockets/rsyslog /zroot/haproxy/var/sockets/rsyslog" \
    "/var/sockets/darwin /zroot/haproxy/var/sockets/darwin" \
    "/var/sockets/haproxy /zroot/haproxy/var/sockets/haproxy" \
    "/var/db/pki /zroot/mongodb/var/db/pki" \
    "/var/sockets/mongodb /zroot/mongodb/var/sockets/mongodb" \
    "/var/db/pki /zroot/portal/var/db/pki" \
    "/home/jails.apache/.zfs-source/home/vlt-os /zroot/portal/home/vlt-os" \
    "/var/sockets/redis /zroot/portal/var/sockets/redis" \
    "/var/sockets/redis /zroot/redis/var/sockets/redis" \
    "/usr/local/etc/redis /zroot/redis/usr/local/etc/redis" \
    "/usr/local/etc/rsyslog.d /zroot/rsyslog/usr/local/etc/rsyslog.d" \
    "/var/db/pki /zroot/rsyslog/var/db/pki" \
    "/var/log/pf /zroot/rsyslog/var/log/pf" \
    "/var/log/api_parser /zroot/rsyslog/var/log/api_parser" \
    "/var/db/darwin /zroot/rsyslog/var/db/darwin" \
    "/var/sockets/darwin /zroot/rsyslog/var/sockets/darwin" \
    "/var/log/darwin /zroot/rsyslog/var/log/darwin" \
    "/var/db/reputation_ctx /zroot/rsyslog/var/db/reputation_ctx" \
    "/zroot/apache/home/vlt-os/vulture_os/services/rsyslogd/config /zroot/rsyslog/home/vlt-os/vulture_os/services/rsyslogd/config" \
    "/var/sockets/rsyslog /zroot/rsyslog/var/sockets/rsyslog" \
    "/zroot/rsyslog/usr/local/etc/filebeat /usr/local/etc/filebeat" \
    "/zroot/rsyslog/usr/local/etc/filebeat /zroot/apache/usr/local/etc/filebeat" \
    "/usr/local/etc/defender.d /zroot/haproxy/usr/local/etc/defender.d" \
    "/usr/local/etc/defender.d /zroot/apache/usr/local/etc/defender.d"; do
        if [ -n "$(/usr/bin/grep "$mount_path" "$file" 2> /dev/null)" ]  ; then
            grep -v "$mount_path" "$file" > $temp_dir/fstab.tmp
            mv "${temp_dir}/fstab.tmp" "$file"
        fi
    done
    /bin/echo "[-] Done"

    /bin/echo "[+] Changing paths in fstab to match new paths in bastille jails"
    for jail in "portal" "apache" "haproxy" "rsyslog" "redis" "mongodb"; do
        sed -i '' "s:/zroot/$jail:/zroot/$jail/root:g" "$file"
    done
    /bin/echo "[-] Done"

    /bin/echo "[+] Mounting fstab"
    mount -a -l -F /etc/fstab
    /bin/echo "[-] Done"
}

initialize

if [ "$(uname -r)" == "13.1-STABLE-HBSD" ] ; then
    update_packages
    stop_services
    mk_jail_system
    verify_services

    finalize

    /bin/echo "[-] Done migrating system!"
    exit 0

fi

# Updating repositories for host
update_repositories

# Updating HardenedBSD system
update_system
/bin/echo "[-] Done updating host system"

# Updating repositories for the host the second time because system update
update_repositories

# Updating repositories of jails
for jail in "haproxy" "apache" "portal" "mongodb" "redis" "rsyslog" ; do
    /bin/echo "[+] Updating repository of jail $jail..."
    update_repositories "$jail_path/$jail"
    /bin/echo "[-] Done"
done

restart_system