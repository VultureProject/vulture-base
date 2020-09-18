#!/bin/sh


if [ "$(/usr/bin/id -u)" != "0" ]; then
   /bin/echo "This script must be run as root" 1>&2
   exit 1
fi

# Get old hostname if exists
if [ -f /etc/rc.conf.hostname ] ; then
    old_hostname="$(/bin/cat /etc/rc.conf.hostname | /usr/bin/sed -E 's/hostname=\"?(.*)\"?/\1/g')"
elif [ -f /tmp/bsdinstall_etc/rc.conf.hostname ] ; then
    old_hostname="$(/bin/cat /tmp/bsdinstall_etc/rc.conf.hostname | /usr/bin/sed -E 's/hostname=\"?(.*)\"?/\1/g')"
fi


if [ $# -ge 1 ] ; then
    /bin/mkdir -p /tmp/bsdinstall_etc/
    /bin/echo "hostname=$1" > /tmp/bsdinstall_etc/rc.conf.hostname
else
    /usr/sbin/bsdinstall hostname
fi

cat /tmp/bsdinstall_etc/rc.conf.hostname
if [ -f /tmp/bsdinstall_etc/rc.conf.hostname ]; then

    grep 'hostname=""' /tmp/bsdinstall_etc/rc.conf.hostname 1>2
    if [ $? -ne 0 ]; then #if == 0 hostname="" so we don't update
        /bin/cat /tmp/bsdinstall_etc/rc.conf.hostname | tr -d '"' > /etc/rc.conf.hostname
        sysrc -f /etc/rc.conf $(cat /etc/rc.conf.hostname)
        . /etc/rc.conf
        /bin/hostname ${hostname}

        # Retrieve management IP address
        ip="$(/bin/cat /usr/local/etc/management.ip)"
        # Ip no management IP - exit
        if [ -z "$ip" ] ; then
            /bin/echo "Management IP address is null - please select 'Management' and retry." >> /dev/stderr
            exit 1
        fi

        /usr/sbin/service vultured status
        vultured_runing=$?
        if [ $vultured_runing -eq 0 ] ; then
            /usr/sbin/service vultured stop
        fi

        # Update /etc/hosts with the new name (take the management IP address)
        /home/vlt-adm/system/write_hostname.sh

        # Be sure that all jails are started
        for jail in apache mongodb redis rsyslog haproxy portal; do
            /usr/sbin/jail -cm "$jail" > /dev/null
        done

        # Initialize internal PKI
        #  On secondary node, this will be overridden later during cluster join
        /home/vlt-os/env/bin/python /home/vlt-os/scripts/pki.py

        # Apache: Hostname change has no impact
        /usr/sbin/jexec apache /usr/sbin/service apache24 restart
        /usr/sbin/jexec portal /usr/sbin/service apache24 restart

        # MongoDB is restarted "as this"
        if ! /usr/sbin/jexec mongodb /usr/sbin/service mongod restart ; then
            /bin/echo "[!] Failed to restart mongodb. Please solve and relaunch $0." > /dev/stderr
            exit 1
        fi

        # Initialize the mongoDB replicaset, if bootstrap is not done yet
        if [ ! -f /home/vlt-os/vulture_os/.install ] ; then
            export hostname=${hostname}
            options="--ssl --sslPEMKeyFile /var/db/pki/node.pem --sslCAFile /var/db/pki/ca.pem"
            # If the management IP is an IPv6 address
            if [ "$(/bin/echo "$ip" | /usr/bin/grep ":")" ] ; then
                options="--ipv6 $options"
            fi
            # Populate mongoDB, if bootstrap is not done yet
            command='/bin/echo rs.initiate\(\{_id:\"Vulture\", members:\[\{_id:0,host:\"'${hostname}':9091\"\}\]\}\) | /usr/local/bin/mongo '${options}' '${hostname}':9091/vulture'
            if /usr/sbin/jexec mongodb /bin/csh -c "$command" ; then
                ## Django migrations
                /home/vlt-adm/gui/django_migration.sh
            else
                /bin/echo "Failed to initialize mongodb node, migrations aborted." >> /dev/stderr
            fi
        elif [ -n "$old_hostname" -a "$old_hostname" != "$hostname" ] ; then # old != new
            echo "Rename replicaset"
            # Change the hostname of the node in MongoDB replicaset configuration
            /home/vlt-os/scripts/replica_rename.py "$old_hostname" "$hostname"
            # Start vultured if it was running
            if [ $vultured_runing -eq 0 ] ; then
                /usr/sbin/service vultured start
            fi
        fi
    fi
fi
