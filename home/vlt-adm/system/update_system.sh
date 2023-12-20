#!/bin/sh

#############
# variables #
#############
temp_dir=""
resolve_strategy="mf"
system_version=""
keep_temp_dir=0
do_update_system=1
do_update_packages=1
download_only=0
use_dnssec=0
clean_cache=0
cron_was_up=0

#############
# functions #
#############
usage() {
    echo "USAGE ${0} OPTIONS"
    echo "OPTIONS:"
    echo "	-D	only download packages/system updates in temporary dir (implies -T)"
    echo "	-T	keep temporary directory"
    echo "	-V	set a custom system update package (as specified by 'hbsd-update -v', only available on HBSD)"
    echo "	-c	clean pkg cache and tempdir at the end of the script (incompatible with -T and -D)"
    echo "	-d	use dnssec while downloading HardenedBSD updates (disabled by default)"
    echo "	-u	do not update system/kernel, only update packages"
    echo "	-s	do not update packages, only update system/kernel"
    echo "	-t tmpdir	temporary directory to use (default is /tmp/vulture_update/, only available on HBSD)"
    echo "	-r strategy	(non-interactive) resolve strategy to pass to hbsd-update script while upgrading system configuration files (see man etcupdate for more info, default is 'mf')"
    exit 1
}

download_system_update() {
    download_dir="$1"
    jail="$2"

    if [ -f /usr/sbin/hbsd-update ] ; then
        options=""
        if [ $use_dnssec -eq 0 ]; then options="${options} -d"; fi
        if [ -n "$jail" ] ; then
            if [ -d /.jail_system ]; then
                # upgrade base jail_system root with local hbsd-update.conf (for "thin" jails)
                options="${options} -r /.jail_system/"
            else
                # use -j flag from hbsd-update to let it handle upgrade of "full" jail
                options="${options} -j $jail"
            fi
        fi
        if [ -n "$system_version" ]; then
            # Add -U as non-last update versions cannot be verified
            echo "[!] Custom version of system update selected, this version will be installed without signature verification!"
            options="${options} -v $system_version -U"
        fi        # Store (-t) and keep (-T) downloads to $download_dir for later use
        # Do not install update yet (-f)
        if [ ! -f ${download_dir}/update.tar ]; then
            /usr/sbin/hbsd-update -t "$download_dir" -T -f $options
        fi
        if [ $? -ne 0 ] ; then return 1 ; fi
    else
        /usr/sbin/freebsd-update --not-running-from-cron fetch > /dev/null
        if [ $? -ne 0 ] ; then return 1 ; fi
    fi
}

# Function used to use appropriate update binary
update_system() {
    download_dir="$1"
    jail="$2"
    if [ -f /usr/sbin/hbsd-update ] ; then
        # If a jail is specified, execute update in it
        if [ -n "$jail" ] ; then
            if [ -d /.jail_system ]; then
                # upgrade base jail_system root with local hbsd-update.conf (for "thin" jails)
                options="-r /.jail_system/"
            else
                # use -j flag from hbsd-update to let it handle upgrade of "full" jail
                options="-j $jail"
            fi
        fi
        if [ -n "$system_version" ]; then
            # Add -U as non-last update versions cannot be verified
            echo "[!] Custom version of system update selected, this version will be installed without signature verification!"
            options="${options} -v $system_version -U"
        fi
        # Store (-t) and keep (-T) downloads to $download_dir for later use
        # Previous download should be present in the 'download_dir' folder already
        if [ -n "$resolve_strategy" ] ; then
            # echo resolve strategy to hbsd-update for non-interactive resolution of conflicts in /etc/ via etcupdate
            /usr/bin/yes "$resolve_strategy" | /usr/sbin/hbsd-update -d -t "$download_dir" -T -D $options
        else
            /usr/sbin/hbsd-update -d -t "$download_dir" -T -D $options
        fi
        if [ $? -ne 0 ] ; then return 1 ; fi
    else
        # If jail, just install do not fetch
        if [ -n "$jail" ] ; then options="-b /zroot/$jail" ; fi
        /usr/sbin/freebsd-update $options install > /dev/null
        if [ $? -ne 0 ] ; then return 1 ; fi
    fi
}


initialize() {
    if [ "$(/usr/bin/id -u)" != "0" ]; then
        /bin/echo "This script must be run as root" 1>&2
        exit 1
    fi

    echo "[$(date +%Y-%m-%dT%H:%M:%S+00:00)] Beginning upgrade"

    trap finalize SIGINT

    /usr/local/bin/sudo -u vlt-os /home/vlt-os/env/bin/python /home/vlt-os/vulture_os/manage.py toggle_maintenance --on 2>/dev/null || true

    if [ -f /etc/rc.conf.proxy ]; then
        . /etc/rc.conf.proxy
        export http_proxy=${http_proxy}
        export https_proxy=${https_proxy}
        export ftp_proxy=${ftp_proxy}
    fi

    # Create temporary directory if none specified
    temp_dir=${temp_dir:="/tmp/vulture_update"}
    mkdir -p $temp_dir || echo "Temp directory exists, keeping"

    # Disable secadm rules if on an HardenedBSD system
    if [ -f /usr/sbin/hbsd-update ] ; then
        echo "[+] Disabling root secadm rules"
        /usr/sbin/service secadm stop || echo "Could not disable secadm rules"
        echo "[-] Done."

        for jail in "mongodb" "apache" "portal"; do
            echo "[+] [${jail}] Disabling secadm rules"
            /usr/sbin/jexec $jail /usr/sbin/service secadm stop || echo "Could not disable secadm rules"
            echo "[-] Done."
        done
    fi

    # Disable harden_rtld: currently breaks many packages upgrade
    _was_rtld=$(/sbin/sysctl -n hardening.harden_rtld)
    /sbin/sysctl hardening.harden_rtld=0
    for jail in "haproxy" "mongodb" "redis" "apache" "portal" "rsyslog"; do
        eval "_was_rtld_${jail}=$(/usr/sbin/jexec $jail /sbin/sysctl -n hardening.harden_rtld)"
        /usr/sbin/jexec $jail /sbin/sysctl hardening.harden_rtld=0 > /dev/null
    done

    # Unlock Vulture packages
    echo "[+] Unlocking Vulture packages..."
    /usr/sbin/pkg unlock -y vulture-base vulture-gui vulture-haproxy vulture-mongodb vulture-redis vulture-rsyslog
    echo "[-] Done."

    if /usr/sbin/service cron status > /dev/null; then
        cron_was_up=1
        process_match="manage.py crontab run "
        # Disable cron during upgrades
        echo "[+] Disabling cron..."
        /usr/sbin/service cron stop
        if /bin/pgrep -qf "${process_match}"; then
            echo "[*] Stopping currently running crons..."
            # send a SIGTERM to close scripts cleanly, if pwait expires after 10m, force kill all remaining scripts
            /bin/pkill -15 -f "${process_match}"
            if ! /bin/pgrep -f "${process_match}" | /usr/bin/xargs /bin/pwait -t10m; then
                echo -e "\033[0;31m[!] Some crons still running after 10 minutes, forcing remaining crons to stop!\033[0m"
                /bin/pgrep -lf "${process_match}"
                /bin/pkill -9 -lf "${process_match}"
            fi
        fi
        echo "[-] Cron disabled"
    fi
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

    if [ $keep_temp_dir -eq 0 ]; then
        echo "[+] Cleaning temporary dir..."
        /bin/rm -rf $temp_dir
        echo "[-] Done."
    fi

    # Re-enable secadm rules if on an HardenedBSD system
    if [ -f /usr/sbin/hbsd-update ] ; then
        echo "[+] Enabling root secadm rules"
        /usr/sbin/service secadm start || echo "Could not enable secadm rules"
        echo "[-] Done."

        for jail in "mongodb" "apache" "portal"; do
            echo "[+] [${jail}] Enabling secadm rules"
            /usr/sbin/jexec $jail /usr/sbin/service secadm start || echo "Could not enable secadm rules"
            echo "[-] Done."
        done
    fi

    # Reset hardeen_rtld to its previous value
    /sbin/sysctl hardening.harden_rtld="${_was_rtld}"
    for jail in "haproxy" "mongodb" "redis" "apache" "portal" "rsyslog"; do
        eval "/usr/sbin/jexec $jail /sbin/sysctl hardening.harden_rtld=\$_was_rtld_$jail" > /dev/null
    done

    # Lock Vulture packages
    echo "[+] Lock Vulture packages..."
    /usr/sbin/pkg lock -y vulture-base vulture-gui vulture-haproxy vulture-mongodb vulture-redis vulture-rsyslog
    echo "[-] Done."

    # Be sure to restart dnsmasq: No side-effect and it deals with dnsmasq configuration changes
    /usr/sbin/service dnsmasq restart

    if [ $cron_was_up -eq 1 ]; then
        # Restart cron after upgrade
        echo "[+] Restarting cron..."
        /usr/sbin/service cron start
        echo "[-] Cron restarted"
    fi

    /usr/local/bin/sudo -u vlt-os /home/vlt-os/env/bin/python /home/vlt-os/vulture_os/manage.py toggle_maintenance --off 2>/dev/null || true

    echo "[$(date +%Y-%m-%dT%H:%M:%S+00:00)] Upgrade finished!"
    exit $err_code
}


####################
# parse parameters #
####################
while getopts 'hDTV:cdust:r:' opt; do
    case "${opt}" in
        D)  download_only=1;
            keep_temp_dir=1;
            ;;
        T)  keep_temp_dir=1;
            ;;
        V)  system_version="${OPTARG}";
            ;;
        c)  clean_cache=1;
            ;;
        d)  use_dnssec=1;
            ;;
        u)  do_update_system=0;
            ;;
        s)  do_update_packages=0;
            ;;
        t)  temp_dir="${OPTARG}";
            ;;
        r)  resolve_strategy="${OPTARG}";
            ;;
        *)  usage;
            ;;
    esac
done
shift $((OPTIND-1))

if [ $clean_cache -gt 0 -a $keep_temp_dir -gt 0 -o $clean_cache -gt 0 -a $download_only -gt 0 ]; then
    echo "[!] Cannot activate -c if -D or -T are set"
    exit 1
fi

initialize

if [ $do_update_packages -gt 0 ]; then
    IGNORE_OSVERSION="yes" /usr/sbin/pkg update -f || finalize 1 "Could not update list of packages"
fi

if [ $download_only -gt 0 ]; then
    if [ $do_update_packages -gt 0 ]; then
        # Fetch updated packages for root system
        IGNORE_OSVERSION="yes" /usr/sbin/pkg fetch -yu || finalize 1 "Failed to download new packages"
        # fetch updated packages for each jail
        for jail in "haproxy" "apache" "portal" "mongodb" "redis" "rsyslog" ; do
            IGNORE_OSVERSION="yes" /usr/sbin/pkg -j $jail update -f || finalize 1 "Could not update list of packages for jail ${jail}"
            IGNORE_OSVERSION="yes" /usr/sbin/pkg -j $jail fetch -yu || finalize 1 "Failed to download new packages for jail ${jail}"
        done
    fi
    if [ $do_update_system -gt 0 ]; then
        download_system_update ${temp_dir} || finalize 1 "Failed to download system upgrades"
    fi
    # exit here, everything has been downloaded
    finalize
fi

if [ $do_update_system -gt 0 ]; then
    /bin/echo "[+] Updating system..."
    download_system_update ${temp_dir} || finalize 1 "Failed to download system upgrades"
    update_system ${temp_dir} || finalize 1 "Failed to install system upgrades"
    secadm_version="$(/usr/sbin/pkg query '%At:%Av' secadm | /usr/bin/grep "FreeBSD_version" | /usr/bin/cut -d : -f 2)"
    if [ -n "$secadm_version" ] && [ "$secadm_version" -lt "$(uname -U)" ]; then
        echo "Forcing upgrade of secadm packages (kernel version mismatch)"
        /usr/sbin/pkg upgrade -yf secadm secadm-kmod
        for jail in "haproxy" "apache" "portal" "mongodb" "redis" "rsyslog" ; do
            /usr/sbin/pkg -j "$jail" upgrade -yf secadm secadm-kmod
        done
    fi
    /bin/echo "[-] Done."
fi

# If no argument or jail asked
for jail in "haproxy" "redis" "mongodb" "rsyslog" ; do
    if [ -z "$1" -o "$1" == "$jail" ] ; then
        /bin/echo "[+] Updating $jail..."

        if [ $do_update_system -gt 0 ]; then
            /bin/echo "[+] Updating jail $jail base system files..."
            download_system_update "$temp_dir" "$jail" || finalize 1 "Failed to download system upgrades for jail ${jail}"
            update_system "$temp_dir" "$jail" || finalize 1 "Failed to install system upgrades in jail ${jail}"
            echo "[-] Ok."
        fi

        if [ $do_update_packages -gt 0 ]; then
            /bin/echo "[+] Updating jail $jail packages..."
            IGNORE_OSVERSION="yes" /usr/sbin/pkg -j "$jail" update -f || finalize 1 "Could not update list of packages for jail ${jail}"
            IGNORE_OSVERSION="yes" /usr/sbin/pkg -j "$jail" upgrade -y || finalize 1 "Could not upgrade packages for jail ${jail}"
            # Upgrade vulture-$jail AFTER, in case of "pkg -j $jail upgrade" has removed some permissions... (like redis)
            IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -y "vulture-$jail" || finalize 1 "Could not upgrade vulture-${jail}"
            echo "[-] Ok."
        fi

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
                if /usr/sbin/jexec "$jail" /usr/sbin/service haproxy status > /dev/null ; then
                    # Reload gracefully
                    /bin/echo "[*] reloading haproxy service..."
                    /usr/sbin/jexec "$jail" /usr/sbin/service haproxy reload
                else
                    # Start service
                    /bin/echo "[*] starting haproxy service..."
                    /usr/sbin/jexec "$jail" /usr/sbin/service haproxy start
                fi
                ;;
            *)
                /usr/sbin/jexec "$jail" /usr/sbin/service "$jail" restart
                ;;
        esac
        echo "[-] $jail updated."
    fi
done

# No parameter, or gui
if [ -z "$1" -o "$1" == "gui" ] ; then
    echo "[+] Updating GUI..."
    if [ $do_update_packages -gt 0 ]; then
        /usr/sbin/jexec apache /usr/sbin/service gunicorn stop
        /usr/sbin/jexec portal /usr/sbin/service gunicorn stop
        echo "[+] Updating apache and portal jails' packages..."
        IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -y vulture-gui  || finalize 1 "Failed to upgrade package vulture-gui"

        /bin/echo "[+] Reloading dnsmasq..."
        # Ensure dnsmasq is up-to-date, as it could be modified during vulture-gui upgrade
        /usr/sbin/service dnsmasq reload || /usr/sbin/service dnsmasq restart
        /bin/echo "[-] dnsmasq reloaded"

        IGNORE_OSVERSION="yes" /usr/sbin/pkg -j apache update -f || finalize 1 "Failed to update the list of packages for the apache jail"
        IGNORE_OSVERSION="yes" /usr/sbin/pkg -j portal update -f || finalize 1 "Failed to update the list of packages for the portal jail"
        IGNORE_OSVERSION="yes" /usr/sbin/pkg -j apache upgrade -y || finalize 1 "Failed to upgrade packages in the apache jail"
        IGNORE_OSVERSION="yes" /usr/sbin/pkg -j portal upgrade -y || finalize 1 "Failed to upgrade packages in the portal jail"
        echo "[-] Ok."
    fi

    if [ $do_update_system -gt 0 ]; then
        echo "[+] Updating jail apache base system files..."
        download_system_update "$temp_dir" "apache" || finalize 1 "Failed to download system upgrades for jail apache"
        update_system "$temp_dir" "apache" || finalize 1 "Failed to install system upgrades in jail apache"
        echo "[-] Ok."
        echo "[+] Updating jail portal base system files..."
        download_system_update "$temp_dir" "portal" || finalize 1 "Failed to download system upgrades for jail portal"
        update_system "$temp_dir" "portal" || finalize 1 "Failed to install system upgrades in jail portal"
        echo "[-] Ok."
    fi
    /usr/sbin/jexec apache /usr/sbin/service gunicorn restart
    /usr/sbin/jexec apache /usr/sbin/service nginx restart
    /usr/sbin/jexec portal /usr/sbin/service gunicorn restart
    echo "[-] GUI updated."
fi

# If no parameter provided, upgrade vulture-base
if [ -z "$1" ] ; then
    if [ $do_update_packages -gt 0 ]; then
        echo "[+] Updating vulture-base ..."
        IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -y vulture-base || finalize 1 "Failed to upgrade vulture-base"

        /bin/echo "[+] Reloading dnsmasq..."
        # Ensure dnsmasq is up-to-date, as it could be modified during vulture-base upgrade
        /usr/sbin/service dnsmasq reload || /usr/sbin/service dnsmasq restart
        /bin/echo "[-] dnsmasq reloaded"

        echo "[-] Vulture-base updated"
    fi
fi


# If no argument - update all
if [ -z "$1" ] ; then
    if [ $do_update_packages -gt 0 ]; then
        echo "[+] Updating all packages on system..."
        IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -y  || finalize 1 "Error while upgrading packages"
        echo "[-] All packages updated"
    fi
fi

# Do not start vultured if the node is not installed
if /usr/local/bin/sudo -u vlt-os /home/vlt-os/env/bin/python /home/vlt-os/vulture_os/manage.py is_node_bootstrapped >/dev/null 2>&1 ; then
    /usr/sbin/service vultured restart
fi

if [ $clean_cache -gt 0 ]; then
    echo "[+] Cleaning pkg cache..."
    /usr/sbin/pkg clean -ay
    echo "[-] Done."
    for jail in "haproxy" "apache" "portal" "mongodb" "redis" "rsyslog" ; do
        echo "[+] Cleaning pkg cache in jail ${jail}..."
        /usr/sbin/pkg -j $jail clean -ay
        echo "[-] Done."
    done
fi

finalize
