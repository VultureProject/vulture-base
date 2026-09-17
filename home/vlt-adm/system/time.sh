#!/bin/sh


tmp_file="/var/tmp/dialog$$"
/bin/rm -f "$tmp_file"
if /usr/bin/command -v bsddialog >/dev/null; then
    dialog_bin="/usr/bin/bsddialog"
else
    dialog_bin="/usr/bin/dialog"
fi

current_ntp="0.freebsd.pool.ntp.org"
if [ -f /etc/rc.conf.ntp ] ; then
    current_ntp="$(/bin/cat /etc/rc.conf.ntp)"
fi

if $dialog_bin --title "Vulture NTP setting" --inputbox "Enter NTP server address" 8 60 "$current_ntp" 2> "$tmp_file"; then
    if [ -f "$tmp_file" ]; then
        ntp=$(/bin/cat "$tmp_file")
        /usr/local/bin/sudo /home/vlt-adm/system/write_ntp.sh "${ntp}"
    fi
    /bin/rm "$tmp_file"
fi
