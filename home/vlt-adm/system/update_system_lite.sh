#!/bin/sh


if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

if [ -f /etc/rc.conf.proxy ]; then
    . /etc/rc.conf.proxy
    export http_proxy=${http_proxy}
    export https_proxy=${https_proxy}
    export ftp_proxy=${ftp_proxy}
fi

# Disable secadm rules if on an HardenedBSD system
if [ -f /usr/sbin/hbsd-update ] ; then
    echo "[*] disabling root secadm rules"
    /usr/sbin/service secadm stop || echo "Could not disable secadm rules"

    for jail in "mongodb" "apache" "portal"; do
        echo "[*] [${jail}] disabling secadm rules"
        /usr/sbin/jexec $jail /usr/sbin/service secadm stop || echo "Could not disable secadm rules"
    done
fi

IGNORE_OSVERSION="yes" /usr/sbin/pkg update -f

# If no argument or jail asked
for jail in "haproxy" "redis" "mongodb" "rsyslog" ; do
    if [ -z "$1" -o "$1" == "$jail" ] ; then
        echo "[-] Updating $jail..."
        IGNORE_OSVERSION="yes" /usr/sbin/pkg -j "$jail" update -f
        IGNORE_OSVERSION="yes" /usr/sbin/pkg -j "$jail" upgrade -y
        # Upgrade vulture-$jail AFTER, in case of "pkg -j $jail upgrade" has removed some permissions... (like redis)
        IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -y "vulture-$jail"
        echo "Ok."
        case "$jail" in
            rsyslog)
                /usr/sbin/jexec "$jail" /usr/sbin/service rsyslogd restart
                ;;
            mongodb)
                /usr/sbin/jexec "$jail" /usr/sbin/service mongod restart
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
        echo "[+] $jail updated."
    fi
done

# If no argument, or Darwin
if [ -z "$1" -o "$1" == "darwin" ] ; then
    /usr/sbin/service darwin stop
    echo "[-] Updating darwin..."
    if [ "$(/usr/sbin/pkg query "%v" darwin)" == "1.2.1-2" ]; then
        IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -fy darwin
    else
        IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -y darwin
    fi
    echo "[+] Darwin updated, starting service"
    /usr/sbin/service darwin start
fi

# No parameter, of gui
if [ -z "$1" -o "$1" == "gui" ] ; then
    echo "[-] Updating GUI..."
    IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -y vulture-gui
    IGNORE_OSVERSION="yes" /usr/sbin/pkg -j apache update -f
    IGNORE_OSVERSION="yes" /usr/sbin/pkg -j portal update -f
    IGNORE_OSVERSION="yes" /usr/sbin/pkg -j apache upgrade -y
    IGNORE_OSVERSION="yes" /usr/sbin/pkg -j portal upgrade -y
    /usr/sbin/jexec apache /usr/sbin/service apache24 restart
    /usr/sbin/jexec portal /usr/sbin/service gunicorn restart
    echo "[+] GUI updated."
fi

# If no parameter provided, upgrade vulture-base
if [ -z "$1" ] ; then
    echo "[-] Updating vulture-base ..."
    IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -y vulture-base

    echo "[+] Vulture-base updated"
fi


# If no argument - update all
if [ -z "$1" ] ; then
    echo "[-] Updating all packages..."
    # First upgrade libevent & gnutls independently to prevent removing of vulture-base (don't know why...)
    IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -y libevent
    IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -y gnutls
    # Then, upgrade all packages
    IGNORE_OSVERSION="yes" /usr/sbin/pkg upgrade -y
    echo "[+] All packages updated"
fi

# Re-enable secadm rules if on an HardenedBSD system
if [ -f /usr/sbin/hbsd-update ] ; then
    echo "[*] enabling root secadm rules"
    /usr/sbin/service secadm start || echo "Could not enable secadm rules"

    for jail in "mongodb" "apache" "portal"; do
        echo "[*] [${jail}] enabling secadm rules"
        /usr/sbin/jexec $jail /usr/sbin/service secadm start || echo "Could not enable secadm rules"
    done
fi

# Do not start vultured if the node is not installed
if [ -f /home/vlt-os/vulture_os/.node_ok ]; then
    /usr/sbin/service vultured restart
fi
