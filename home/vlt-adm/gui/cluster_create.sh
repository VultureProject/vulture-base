#!/bin/sh

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

username=$1
password=$2
confirm_password=$2

if [ -z "$username" ]; then
    echo -n "Username: "
    read username
fi

if [ -z "$password" ]; then
    echo -n "Password: "
    stty -echo
    read password
    stty echo
    echo ""
fi

if [ -z "$confirm_password" ]; then
    echo -n "Confirm Password: "
    stty -echo
    read confirm_password
    stty echo
    echo ""
fi

if [ "$password" = "$confirm_password" ]; then
    # Unset proxy to contact the GUI (myself)
    export http_proxy=""
    export https_proxy=""
    export ftp_proxy=""

    # Do a first curl to create log files
    echo "[+] Try to contact GUI ..."
    curl -XGET -kw "Status  code : %{http_code}\n"  -o /dev/null https://$(hostname):8000/ 2> /dev/null

    /usr/sbin/jexec redis service redis restart
    /home/jails.apache/.zfs-source/home/vlt-os/bootstrap/cluster_create $username $password

    # Restart apache service to refresh code and conf
    /usr/sbin/jexec apache /usr/sbin/service apache24 restart

    /usr/sbin/service vultured start
else
    echo "\e[31mPasswords mismatch\e[0m"
    exit
fi

