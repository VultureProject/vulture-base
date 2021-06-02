#!/bin/sh


tmp_file="/var/tmp/dialog$$"
/bin/rm -f "$tmp_file"

current_ntp="0.freebsd.pool.ntp.org"
if [ -f /etc/rc.conf.ntp ] ; then
    current_ntp="$(/bin/cat /etc/rc.conf.ntp)"
fi

if /usr/bin/dialog --title "Vulture NTP setting" --inputbox "Enter NTP server address" 8 60 "$current_ntp" 2> "$tmp_file"; then
    if [ -f "$tmp_file" ]; then
        ntp=$(/bin/cat "$tmp_file")
        /usr/local/bin/sudo /home/vlt-adm/system/write_ntp.sh "${ntp}"
    fi
    /bin/rm "$tmp_file"
fi
