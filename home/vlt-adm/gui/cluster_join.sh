#!/bin/sh

if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

master_hostname=$1
master_ip=$2
api_key=$3

if [ -z "${master_hostname}" ]; then
    echo -n "Master hostname: "
    read master_hostname
fi

if [ -z "${master_ip}" ]; then
    echo -n "Master IP (without bracket for IPv6):"
    read master_ip
fi

if [ -z "${api_key}" ]; then
    echo -n "Cluster APIKey: "
    read api_key
fi

/home/vlt-os/scripts/add_to_hosts.py "$master_hostname" "$master_ip"

/usr/sbin/jexec redis service redis restart
/usr/sbin/jexec apache service gunicorn stop
/usr/sbin/jexec portal service gunicorn stop
/usr/sbin/service vultured stop

if echo "$master_ip" | grep ":" ; then
    master_ip="[${master_ip}]"
fi

/zroot/apache/home/vlt-os/bootstrap/cluster_join "$master_hostname" "$master_ip" "$api_key"

/usr/sbin/service vultured start
/usr/sbin/jexec apache service gunicorn start
/usr/sbin/jexec portal service gunicorn start
# CA cert is collected during cluster_join but not the key
cat /var/db/pki/Vulture_PKI_*.key > /var/db/pki/ca.key