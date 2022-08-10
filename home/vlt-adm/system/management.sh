#!/bin/sh


if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

ip="$1"

/sbin/ifconfig | grep "$ip" > /dev/null
if [ "$?" == 0 ]; then
    /bin/echo "$ip" > /usr/local/etc/management.ip

    #Update /etc/hosts with the new Management IP address
    /home/vlt-adm/system/write_hostname.sh

    #Update sentinel and redis with the new Management IP address
    if [ "$(/usr/sbin/jls | /usr/bin/grep "redis")" == "" ]; then
        /usr/sbin/jail -cm redis > /dev/null
    fi
    /usr/sbin/jexec redis /usr/sbin/service redis stop > /dev/null
    /usr/sbin/jexec redis /usr/sbin/service sentinel stop > /dev/null

    /bin/cat /usr/local/etc/redis/templates/redis.tpl | /usr/bin/sed "s/{{ management_ip }}/${ip}/" > /usr/local/etc/redis/redis.conf
    /bin/cat /usr/local/etc/redis/templates/sentinel.tpl | /usr/bin/sed "s/{{ management_ip }}/${ip}/" > /usr/local/etc/redis/sentinel.conf

    /usr/sbin/jexec redis /usr/sbin/service redis start > /dev/null
    /usr/sbin/jexec redis /usr/sbin/service sentinel start > /dev/null

    #Update Rsyslog jail conf
    case $ip in
        *:*) /usr/bin/sed -Ei '' $'s/^.+#RSYSLOGJAILIP$/\t ip6.addr += '$ip$'; \t\t\t\t\t #RSYSLOGJAILIP/' "/etc/jail.conf";;
        *) /usr/bin/sed -Ei '' $'s/^.+#RSYSLOGJAILIP$/\t ip4.addr += '$ip$'; \t\t\t\t\t #RSYSLOGJAILIP/' "/etc/jail.conf";;
    esac

    /usr/sbin/service jail restart rsyslog

    /usr/local/bin/pfctl-init.sh
    /sbin/pfctl -f /usr/local/etc/pf.conf

    # The Node has been removed of the replicaset, restart mongodb to re-initiate
    /usr/sbin/jexec mongodb service mongod restart

    # If boostrap has already be done,
    if /usr/local/bin/sudo -u vlt-os /home/vlt-os/env/bin/python /home/vlt-os/vulture_os/manage.py is_node_bootstrapped >/dev/null 2>&1 ; then
        # update node management ip in Mongo
        /home/vlt-os/env/bin/python /home/vlt-os/vulture_os/manage.py shell -c "from system.cluster.models import Node ; n = Node.objects.get(name=\"`hostname`\") ; n.management_ip = \"$ip\" ; n.save()"
        # update management ip in apache conf
        /home/vlt-os/env/bin/python /home/vlt-os/vulture_os/manage.py shell -c "from services.apache.apache import reload_conf ; import logging ; logger=logging.getLogger('services') ; reload_conf(logger)"
    fi
else
    /bin/echo "Invalid IP Address !"
fi