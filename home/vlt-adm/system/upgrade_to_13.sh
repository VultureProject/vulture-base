#!/usr/bin/env sh

SCRIPT=$(realpath "$0")
FOLDER="${SCRIPT%/*}"

COLOR_OFF='\033[0m'
COLOR_RED='\033[0;31m'

temp_dir="/var/tmp/update"
new_be="Vulture-HBSD13-$(date -Idate)"

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
    if [ -n "$jail" ] ; then
        options="${options} -n -j $jail"
    else
        new_be="Vulture-HBSD13-$(date +%Y%m%d%H%M%S)"
        options="${options} -b $new_be"
    fi
    /bin/echo "[+] Updating base system..."
    /usr/bin/yes "mf" | /usr/sbin/hbsd-update -d -t "$temp_dir" -T -D $options || finalize 1  "[/] System update failed"
    /bin/echo "[-] Done with update"
}

update_packages(){
    /bin/echo "[+] Bootstrap pkg"
    IGNORE_OSVERSION="yes" /usr/sbin/pkg bootstrap -fy || finalize 1 "Could not bootstrap pkg"
    /bin/echo "[-] Done"
    /bin/echo "[+] Updating root pkg repository catalogue"
    IGNORE_OSVERSION="yes" /usr/sbin/pkg update -f || finalize 1 "Could not update list of packages"
    /bin/echo "[-] Done"
    /bin/echo "[+] Clear pkg cache before fetching"
    IGNORE_OSVERSION="yes" /usr/sbin/pkg clean -ya || finalize 1 "Could not clear pkg cache"
    /bin/echo "[-] Done clearing pkg cache"
    # Fetch updated packages for root system
    IGNORE_OSVERSION="yes" /usr/sbin/pkg fetch -yu || finalize 1 "Failed to download packages"
    # Fetch updated packages for jails
    for jail in "haproxy" "rsyslog" "redis" "mongodb" "portal" "apache" ; do
        IGNORE_OSVERSION="yes" /usr/sbin/pkg -j $jail fetch -yu || finalize 1 "Failed to download packages for jail $jail"
    done
    /bin/echo "[-] Done"

    /bin/echo "[+] Upgrading host system packages"
    /usr/sbin/pkg unlock -y vulture-base vulture-gui vulture-haproxy vulture-mongodb vulture-redis vulture-rsyslog
    IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -fy
    /usr/sbin/pkg lock -y vulture-base vulture-gui vulture-haproxy vulture-mongodb vulture-redis vulture-rsyslog
    /bin/echo "[-] Done"

    /bin/echo "[+] Reloading dnsmasq..."
    # Ensure dnsmasq config is up-to-date, as it could be modified during vulture-gui upgrade
    /usr/sbin/service dnsmasq reload || /usr/sbin/service dnsmasq restart
    /bin/echo "[-] dnsmasq reloaded"

    /bin/echo "[+] Upgrading jail's packages"
    for jail in "haproxy" "rsyslog" "redis" "mongodb" "portal" "apache" ; do
        IGNORE_OSVERSION="yes" /usr/sbin/pkg -j $jail upgrade -fy
    done
    /bin/echo "[-] Done"

    # Load secadm module into kernel and start
    /bin/echo "[+] Upgrading secadm"
    IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -fy secadm secadm-kmod
    /bin/echo "[-] Done"
    kldload secadm
    /usr/sbin/service secadm restart

    /bin/echo "[+] Cleaning pkg cache..."
    IGNORE_OSVERSION="yes" /usr/sbin/pkg clean -ay
    for jail in "haproxy" "rsyslog" "redis" "mongodb" "portal" "apache" ; do
        IGNORE_OSVERSION="yes" /usr/sbin/pkg -j $jail clean -ay
    done
    /bin/echo "[-] Done"
}


restart_and_continue(){
    /bin/echo "[+] Setting up startup script to continue upgrade..."
    # enable script to be run on startup
    tmp_be_mount="$(/usr/bin/mktemp -d)"
    /sbin/bectl mount "$new_be" "$tmp_be_mount" || finalize 1 "Could not mount Boot Environment"
    /bin/echo "@reboot root sleep 30 && /bin/sh $SCRIPT" > "${tmp_be_mount}/etc/cron.d/vulture_update" || finalize 1  "[/] Failed to setup startup script"
    # Add a temporary message to end of MOTD to warn about the ongoing upgrade
    /usr/bin/sed -i '' '$s/.*/[5m[38;5;196mUpgrade in progress, your machine will reboot shortly, please wait patiently![0m/' "${tmp_be_mount}/etc/motd.template"
    /usr/bin/sed -i '' 's+welcome=/etc/motd+welcome=/var/run/motd+' "${tmp_be_mount}/etc/login.conf"
    /usr/bin/cap_mkdb "${tmp_be_mount}/etc/login.conf"
    /sbin/bectl umount "$new_be"
    /usr/bin/touch ${temp_dir}/upgrading
    /bin/echo "[-] Ok"
    /bin/echo "[+] Rebooting system"
    /sbin/shutdown -r now
    /bin/echo "[-] Ok"
    exit 0
}


clean_and_restart() {
    /bin/echo "[+] Cleaning up..."
    if [ -e /etc/cron.d/vulture_update ]; then
        /bin/rm -f /etc/cron.d/vulture_update
    fi

    /bin/echo "[+] Cleaning temporary dir..."
    /bin/rm -rf $temp_dir
    /bin/echo "[-] Done"

    /bin/echo "" >> /etc/motd.template
    /usr/bin/sed -i '' '$s/.*/[38;5;10mYour system is now on HardenedBSD 13, welcome back![0m/' /etc/motd.template

    /usr/bin/printf "${COLOR_RED}"
    /bin/echo "WARNING: a new Boot Environment was created during the upgrade, please review existing BEs and delete those no longer necessary!"
    /sbin/bectl list -H
    /usr/bin/printf "${COLOR_OFF}"

    /bin/echo "[+] Rebooting system"
    /sbin/shutdown -r now

    exit 0
}


finalize() {
    # set default in case err_code is not specified
    err_code=${1:-0}
    err_message=$2

    if [ -n "$err_message" ]; then
        /bin/echo ""
        /usr/bin/printf "[!] ${COLOR_RED}${err_message}${COLOR_OFF}\n"
        /bin/echo ""
    fi

    /bin/echo "[+] Cleaning temporary dir..."
    /bin/rm -rf $temp_dir
    /bin/echo "[-] Done"

    # Re-enable secadm rules
    /bin/echo "[+] Enabling root secadm rules"
    /usr/sbin/service secadm start || /bin/echo "Could not enable secadm rules"
    /bin/echo "[-] Done"

    for jail in "mongodb" "apache" "portal"; do
        /bin/echo "[+] [${jail}] Enabling secadm rules"
        /usr/sbin/jexec $jail /usr/sbin/service secadm start || /bin/echo "Could not enable secadm rules"
        /bin/echo "[-] Done"
    done

    # Be sure to restart dnsmasq: No side-effect and it deals with dnsmasq configuration changes
    /usr/sbin/service dnsmasq restart

    # remove script from running at start up
    rm -f /etc/cron.d/vulture_update

    exit $err_code
}

usage() {
    /bin/echo "USAGE ${0} [-y]"
    /bin/echo "OPTIONS:"
    /bin/echo "	-y	start the upgrade whitout asking for user confirmation (implicit consent)"
    exit 1
}

initialize() {
    if [ "$(/usr/bin/id -u)" != "0" ]; then
        /bin/echo "This script must be run as root" 1>&2
        exit 1
    fi

    trap finalize INT

    if [ -f /etc/rc.conf.proxy ]; then
        . /etc/rc.conf.proxy
        export http_proxy="${http_proxy}"
        export https_proxy="${https_proxy}"
        export ftp_proxy="${ftp_proxy}"
    fi

    # Create temporary directory if it does not exist
    /bin/mkdir -p $temp_dir || /bin/echo "Temp directory exists, keeping"

    # Disable secadm rules
    /bin/echo "[+] Disabling root secadm rules"
    /usr/sbin/service secadm stop || /bin/echo "Could not disable secadm rules"
    /bin/echo "[-] Done"

    for jail in "mongodb" "apache" "portal"; do
        /bin/echo "[+] [${jail}] Disabling secadm rules"
        /usr/sbin/jexec $jail /usr/sbin/service secadm stop || /bin/echo "Could not disable secadm rules"
        /bin/echo "[-] Done"
    done
}


check_preconditions(){
    if /usr/sbin/pkg version -qRl '<' | grep 'vulture-' > /dev/null; then
        # Show necessary packages to be updated
        /usr/bin/printf "${COLOR_RED}"
        /usr/sbin/pkg version -qRl '<' | grep 'vulture-'
        /usr/bin/printf "${COLOR_OFF}"
        finalize 1 "Some packages are not up to date, please run /home/vlt-adm/system/update_system.sh before trying to migrate"
    fi
}


stop_services(){
    # Vultured
    /bin/echo "[+] Stopping vultured..."
    /usr/sbin/service vultured stop || /usr/bin/true
    /bin/echo "[-] Done"

    # Crontabs
    if /usr/sbin/service cron status > /dev/null; then
        /bin/echo "[+] Stopping crontabs..."
        process_match="manage.py crontab run "
        # Disable cron during upgrades
        echo "[+] Disabling cron..."
        /usr/sbin/service cron stop
        if /bin/pgrep -qf "${process_match}"; then
            echo "[*] Stopping currently running crons..."
            # # send a SIGTERM to close scripts cleanly, if pwait expires after 10m, force kill all remaining scripts
            /bin/pkill -15 -f "${process_match}"
            if ! /bin/pgrep -f "${process_match}" | /usr/bin/xargs /bin/pwait -t10m; then
                /usr/bin/printf "\033[0;31m[!] Some crons still running after 10 minutes, forcing remaining crons to stop!\033[0m\n"
                /bin/pgrep -lf "${process_match}"
                /bin/pkill -9 -lf "${process_match}"
            fi
        fi
        echo "[-] Cron disabled"
    fi

    # Apache
    /bin/echo "[+] [apache] Stopping nginx..."
    jexec apache service nginx stop || /usr/bin/true
    /bin/echo "[-] Done"
    /bin/echo "[+] [apache] Stopping gunicorn..."
    jexec apache service gunicorn stop || /usr/bin/true
    /bin/echo "[-] Done"

    # mongodb
    /bin/echo "[+] Stopping mongodb..."
    jexec mongodb service mongod stop || /usr/bin/true
    /bin/echo "[-] Done"

    # rsyslog
    /bin/echo "[+] Stopping rsyslog..."
    jexec rsyslog service rsyslogd stop || /usr/bin/true
    /bin/echo "[-] Done"

    # portal
    /bin/echo "[+] [portal] Stopping gunicorn..."
    jexec portal service gunicorn stop || /usr/bin/true
    /bin/echo "[-] Done"

    # haproxy
    /bin/echo "[+] [haproxy] Stopping haproxy..."
    jexec haproxy service haproxy stop || /usr/bin/true
    /bin/echo "[-] Done"

    # redis
    /bin/echo "[+] [redis] Stopping redis..."
    jexec redis service redis stop || /usr/bin/true
    /bin/echo "[-] Done"
}

if [ ! -e ${temp_dir}/upgrading ] ; then
    _run_ok=0

    while getopts "y" flag;
    do
        case "${flag}" in
            y) _run_ok=1;
            ;;
            *) usage;
            ;;
        esac
    done

    answer=""
    if [ $_run_ok -ne 1 ]; then
        /bin/echo -n "Do you wish to upgrade your node? It will become unavailable while it downloads and installs upgrades for the base system, jails and packages! [yN]: "
        read -r  answer
        case "${answer}" in
            y|Y|yes|Yes|YES)
            # Do nothing, continue
            ;;
            *)  /bin/echo "Upgrade canceled."
                exit 0;
            ;;
        esac
    fi

    if [ "$(uname -K)" -gt 1300000 ]; then
        /bin/echo "Your system seems to already be on HBSD13, nothing to do!"
        /usr/bin/head -25 /etc/motd > /etc/motd.template
        exit 0
    else
        initialize

        check_preconditions

        /bin/echo "Upgrade started!"

        # Updating repositories for host
        ${FOLDER}/register_vulture_repos.sh
        # Updating repositories for each jail
        for jail in "portal" "apache" "haproxy" "rsyslog" "redis" "mongodb"; do
            ${FOLDER}/register_vulture_repos.sh /zroot/${jail}
            update_system $jail
        done

        # Updating HardenedBSD system
        update_system
        /bin/echo "[-] Done updating host system"

        restart_and_continue
    fi
else
    initialize

    log_file=/var/log/upgrade_to_13.log
    /bin/echo "Output will be sent to $log_file"

    exec 3>&1 4>&2
    trap 'exec 2>&4 1>&3' 0 1 2 3
    exec 1>>$log_file 2>&1

    /bin/echo "Beggining Upgrade"

    # Updating repositories for the host the second time because system has been updated
    ${FOLDER}/register_vulture_repos.sh

    stop_services
    update_packages

    clean_and_restart
fi
