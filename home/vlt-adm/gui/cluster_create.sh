#!/bin/sh

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

echo -n "Username: "
read username

echo -n "Password: "
stty -echo 
read password
stty echo
echo ""

echo -n "Confirm Password: "
stty -echo 
read confirm_password
stty echo
echo ""

if [ "$password" = "$confirm_password" ]; then
    # Unset proxy to contact the GUI (myself)
    export http_proxy=""
    export https_proxy=""
    export ftp_proxy=""

    # Do a first curl to create log files
    echo "[+] Try to contact GUI ..."
    curl -XGET -kw "Status  code : %{http_code}\n"  -o /dev/null https://$(hostname):8000/ 2> /dev/null

    /usr/sbin/jexec redis service redis restart
    /usr/sbin/jexec apache /home/vlt-os/bootstrap/cluster_create $username $password

    /usr/sbin/service vultured start

    #FIXME: Handle error
    touch /home/vlt-os/vulture_os/.node_ok
else
    echo "\e[31mPasswords mismatch\e[0m"
    exit
fi

