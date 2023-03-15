#!/usr/bin/env sh

SCRIPT=$(realpath "$0")
FOLDER="${SCRIPT%/*}"

COLOR_OFF='\033[0m'
COLOR_RED='\033[0;31m'

temp_dir="/var/tmp/update"

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
        options="-j $jail"
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

    /bin/echo "[+] Updating vulture-base"
    IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -fy vulture-base
    /bin/echo "[-] Done"

    /bin/echo "[+] Reloading dnsmasq..."
    # Ensure dnsmasq config is up-to-date, as it could be modified during vulture-base upgrade
    /usr/sbin/service dnsmasq reload || /usr/sbin/service dnsmasq restart
    /bin/echo "[-] Done"

    /bin/echo "[+] Upgrading host system packages"
    IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -fy
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
    /bin/echo "@reboot root sleep 10 && /bin/sh $SCRIPT" > /etc/cron.d/vulture_update || finalize 1  "[/] Failed to setup startup script"
    /usr/bin/touch ${temp_dir}/upgrading
    # Add a temporary message to end of MOTD to warn about the ongoing upgrade
    /usr/bin/sed -i '' '$s/.*/[5m[38;5;196mUpgrade in progress, your machine will reboot shortly, please wait patiently![0m/' /etc/motd.template
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
        /bin/echo "[!] ${COLOR_RED}${err_message}${COLOR_OFF}"
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

    trap finalize SIGINT

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
        echo -e "${COLOR_RED}"
        /usr/sbin/pkg version -qRl '<' | grep 'vulture-'
        echo -e "${COLOR_OFF}"
        finalize 1 "Some packages are not up to date, please run /home/vlt-adm/system/update_system.sh before trying to migrate"
    fi
}


stop_services(){
    # Vultured
    /bin/echo "[+] Stopping vultured..."
    /usr/sbin/service vultured stop || /usr/bin/true
    /bin/echo "[-] Done"

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
