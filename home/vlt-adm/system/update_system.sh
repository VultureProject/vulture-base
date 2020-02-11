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

/usr/sbin/pkg update -f
echo -n "Updating system ..."
/usr/sbin/freebsd-update --not-running-from-cron fetch install > /dev/null
echo "ok."

# If no argument or jail asked
for jail in "haproxy" "redis" "mongodb" "rsyslog" ; do
    if [ -z "$1" -o "$1" == "$jail" ] ; then
        echo "[-] Updating $jail ..."
        /usr/sbin/pkg -j "$jail" update -f
        /usr/sbin/pkg -j "$jail" upgrade -y
        # Upgrade vulture-$jail AFTER, in case of "pkg -j $jail upgrade" has removed some permissions... (like redis)
        /usr/sbin/pkg upgrade -y "vulture-$jail"
        echo -n "[-] Updating jail base system files ..."
        /usr/sbin/freebsd-update -b "/zroot/$jail" --not-running-from-cron fetch install > /dev/null
        echo "ok."
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
            *)
                /usr/sbin/jexec "$jail" /usr/sbin/service "$jail" restart
                ;;
        esac
        echo "[+] $jail updated."
    fi
done

# No parameter, of gui
if [ -z "$1" -o "$1" == "gui" ] ; then
    /usr/sbin/pkg upgrade -y "vulture-gui"
    /usr/sbin/pkg -j apache update -f
    /usr/sbin/pkg -j portal update -f
    /usr/sbin/pkg -j apache upgrade -y
    /usr/sbin/pkg -j portal upgrade -y
    /usr/sbin/freebsd-update -b "/zroot/apache" --not-running-from-cron fetch install > /dev/null
    /usr/sbin/freebsd-update -b "/zroot/portal" --not-running-from-cron fetch install > /dev/null
    /usr/sbin/jexec apache /usr/sbin/service apache24 restart
    /usr/sbin/jexec portal /usr/sbin/service apache24 restart
fi

# If no parameter provided, upgrade vulture-base
if [ -z "$1" ] ; then
    echo "[-] Updating vulture-base ..."
    /usr/sbin/pkg upgrade -y vulture-base

    /home/vlt-adm/bootstrap/install-kernel.sh
    /usr/sbin/service secadm restart
    
    echo "[+] Vulture-base updated"
fi


# If no argument, or Darwin
if [ -z "$1" -o "$1" == "darwin" ] ; then
    /usr/sbin/service darwin stop
    echo "[-] Updating darwin ..."
    if [ "$(/usr/sbin/pkg query "%v" darwin)" == "1.2.1-2" ]; then
        /usr/sbin/pkg upgrade -fy darwin
    else
        /usr/sbin/pkg upgrade -y darwin
    fi
    echo "[+] Darwin updated, starting service"
    /usr/sbin/service darwin start
fi

# If no argument - update all
if [ -z "$1" ] ; then
    echo "[-] Updating all packages ..."
    # First upgrade libevent & gnutls independently to prevent removing of vulture-base (don't know why...)
    /usr/sbin/pkg upgrade -y libevent
    /usr/sbin/pkg upgrade -y gnutls
    # Then, upgrade all packages
    /usr/sbin/pkg upgrade -y
    echo "[+] All packages updated"
    /usr/sbin/service vultured restart
    /usr/sbin/service netdata restart
fi
