#!/bin/sh


if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

management_ip="$1"
internet_ip="${2:-$management_ip}"
backends_outgoing_ip="${3:-$management_ip}"
logom_outgoing_ip="${4:-$management_ip}"

/sbin/ifconfig | grep "$management_ip" > /dev/null
if [ "$?" == 0 ]; then
    # update node network ips in /etc/rc.conf.d/network
    /usr/sbin/sysrc -f /etc/rc.conf.d/network management_ip=$management_ip internet_ip=$internet_ip backends_outgoing_ip=$backends_outgoing_ip logom_outgoing_ip=$logom_outgoing_ip

    #Update /etc/hosts with the new Management IP address
    /home/vlt-adm/system/write_hostname.sh

    #Update sentinel and redis with the new Management IP address
    if [ "$(/usr/sbin/jls | /usr/bin/grep "redis")" == "" ]; then
        /usr/sbin/jail -cm redis > /dev/null
    fi
    /usr/sbin/jexec redis /usr/sbin/service redis stop > /dev/null
    /usr/sbin/jexec redis /usr/sbin/service sentinel stop > /dev/null

    /bin/cat /usr/local/etc/redis/templates/redis.tpl | /usr/bin/sed "s/{{ management_ip }}/${management_ip}/" > /usr/local/etc/redis/redis.conf
    /bin/cat /usr/local/etc/redis/templates/sentinel.tpl | /usr/bin/sed "s/{{ management_ip }}/${management_ip}/" > /usr/local/etc/redis/sentinel.conf

    /usr/sbin/jexec redis /usr/sbin/service redis start > /dev/null
    /usr/sbin/jexec redis /usr/sbin/service sentinel start > /dev/null

    #Update Rsyslog jail conf
    case $management_ip in
        *:*) /usr/bin/sed -Ei '' $'s/^.+#RSYSLOGJAILIP$/\t ip6.addr += '$management_ip$'; \t\t\t\t\t #RSYSLOGJAILIP/' "/etc/jail.conf";;
        *) /usr/bin/sed -Ei '' $'s/^.+#RSYSLOGJAILIP$/\t ip4.addr += '$management_ip$'; \t\t\t\t\t #RSYSLOGJAILIP/' "/etc/jail.conf";;
    esac

    /usr/sbin/service jail restart rsyslog

    # The Node has been removed of the replicaset, restart mongodb to re-initiate
    /usr/sbin/jexec mongodb service mongod restart

    # If boostrap has already be done,
    if /usr/local/bin/sudo -u vlt-os /home/vlt-os/env/bin/python /home/vlt-os/vulture_os/manage.py is_node_bootstrapped >/dev/null 2>&1 ; then
        # update node network ips in Mongo
        /usr/local/bin/sudo -u vlt-os /home/vlt-os/env/bin/python /home/vlt-os/vulture_os/manage.py shell -c "from system.cluster.models import Node ; n = Node.objects.get(name=\"`hostname`\") ; n.management_ip = \"$management_ip\" ; n.internet_ip = \"$internet_ip\" ; n.backends_outgoing_ip = \"$backends_outgoing_ip\" ; n.logom_outgoing_ip = \"$logom_outgoing_ip\" ; n.save()"
        # reload apache service
	/usr/Sbin/jexec apache /usr/sbin/service apache24 reload
        # reload pf configuration
        /usr/local/bin/sudo -u vlt-os /home/vlt-os/env/bin/python /home/vlt-os/vulture_os/manage.py shell -c 'from system.cluster.models import Cluster ; Cluster.api_request("services.pf.pf.gen_config")'

    else
        /usr/local/bin/pfctl-init.sh
    fi
else
    /bin/echo "Invalid IP Address !"
fi
