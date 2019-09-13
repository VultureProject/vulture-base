#!/bin/sh


tmp_file="/var/tmp/dialog$$"
/bin/rm -f "$tmp_file"

if /usr/bin/dialog --title "Vulture NTP setting" --inputbox "Enter NTP server address" 8 60 "0.freebsd.pool.ntp.org" 2> "$tmp_file"; then
    if [ -f "$tmp_file" ]; then
        ntp=$(/bin/cat "$tmp_file")
        /usr/local/bin/sudo /home/vlt-adm/system/write_ntp.sh "${ntp}"
    fi
    /bin/rm "$tmp_file"
fi
