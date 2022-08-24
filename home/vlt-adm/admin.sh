#!/bin/sh

# Define the dialog exit status codes
DIALOG_OK=0
DIALOG_CANCEL=1
DIALOG_HELP=2
DIALOG_EXTRA=3
DIALOG_ITEM_HELP=4
DIALOG_ESC=255

JAILS_DIR="/zroot"

# Function used to check jails and install them
check_jails() {
    for jail in apache mongodb redis rsyslog haproxy portal; do
        # Do not check if jail is up, because there can be some tasks that have not been done (eg: pkg install mongodb)
        # /usr/bin/clear

        if [ ! -d /zroot/${jail} ]; then
            /bin/echo "Updating jail ${jail} ..."
                /usr/local/bin/sudo /home/vlt-adm/bootstrap/mkjail-${jail}.sh
        fi

    done
}


# Create a temporary file and make sure it goes away when we're dome
tmp_file="/var/tmp/dialog$$"
while :
do
    /usr/bin/dialog --clear --colors --title "Welcome on Vulture OS" --menu "Please choose an action" 20 100 13 \
    "keymap" "Keyboard config"      \
    "time" "Time config"            \
    "password" "Modify vlt-adm's password" \
    "geli_change" "Modify FDE password" \
    "email" "Define Email address to send alerts to" \
    "network_ips" "Change Node Network IPs" \
    "proxy" "HTTP Proxy config"     \
    "netconfig" "Network config"    \
    "hostname" "Hostname config"    \
    "shell" "CSH Shell"        \
    "rootshell" "ROOT Shell"        \
    "update" "Update OS"            \
    "exit" "Exit" --stdout > "$tmp_file"

    return_value=$?
    case "$return_value" in
        "$DIALOG_OK")
            action="$(/bin/cat "$tmp_file")"

            case "$action" in
                "email")
                    /bin/rm -f "$tmp_file"
                    email=`grep '^root:' /etc/mail/aliases | sed -E 's/^.*:.([a-zA-Z0-9_\.-]+@[a-zA-Z0-9_\.-]+)$/\1/g'`
                    if /usr/bin/dialog --title "Vulture Alert Email address" --inputbox "Enter the email address to send alerts to" 8 60 "${email}" --stdout > "$tmp_file"; then
                        email="$(/bin/cat "$tmp_file")"
                        /bin/rm "$tmp_file"

                        /usr/local/bin/sudo /home/vlt-adm/system/write_aliases.sh "${email}"
                    fi
                    ;;
                "password")
                    /usr/bin/passwd vlt-adm
                    ;;
                "geli_change")
                    if /usr/bin/dialog --title "Vulture Encryption passphrase" --inputbox "Enter a new encryption passphrase" 8 60 "" --stdout > "$tmp_file"; then
                        passphrase="$(/bin/cat "$tmp_file")"
                        /bin/rm "$tmp_file"
                        /usr/local/bin/sudo /home/vlt-adm/system/geli-passphrase.sh "${passphrase}"
                    fi
                    ;;
                "network_ips")
                    check_jails

                    /bin/rm -f "$tmp_file"

                    management_ip="$(/usr/sbin/sysrc -f /etc/rc.conf.d/network -n management_ip 2> /dev/null)"
                    if [ "$?" == 1 ]; then
                        management_ip="$(/sbin/ifconfig | /usr/bin/grep inet | /usr/bin/grep -v '127.0.0.1' | /usr/bin/grep -v ' ::1 ' \
                        | /usr/bin/grep -v 'fe80:' | /usr/bin/awk '{print $2}' | /usr/bin/awk -vRS="" -vOFS=' ' '$1=$1' | cut -d " " -f1)"
                    fi

                    internet_ip="$(/usr/sbin/sysrc -f /etc/rc.conf.d/network -n internet_ip 2> /dev/null)"
                    internet_ip="${internet_ip:-${management_ip}}"
                    backends_outgoing_ip="$(/usr/sbin/sysrc -f /etc/rc.conf.d/network -n backends_outgoing_ip 2> /dev/null)"
                    backends_outgoing_ip="${backends_outgoing_ip:-${management_ip}}"
                    logom_outgoing_ip="$(/usr/sbin/sysrc -f /etc/rc.conf.d/network -n logom_outgoing_ip 2> /dev/null)"
                    logom_outgoing_ip="${logom_outgoing_ip:-${management_ip}}"

                    if /usr/bin/dialog --title "Vulture Node Network settings" --form "Choose the Node's network IP Addresses" 14 60 8 \
                    "Management IP Address:" 1 1 "$management_ip" 1 25 25 30 \
                    "Internet IP:" 3 1 "$internet_ip" 3 25 25 30 \
                    "Backends Outgoing IP:" 5 1 "$backends_outgoing_ip" 5 25 25 30 \
                    "LogOM Outgoing IP:" 7 1 "$logom_outgoing_ip" 7 25 25 30 \
                    --stdout > "$tmp_file"; then

                        management_ip="$(/usr/bin/sed -n 1p "$tmp_file")"
                        internet_ip="$(/usr/bin/sed -n 2p "$tmp_file")"
                        backends_outgoing_ip="$(/usr/bin/sed -n 3p "$tmp_file")"
                        logom_outgoing_ip="$(/usr/bin/sed -n 4p "$tmp_file")"

                        /bin/rm "$tmp_file"

                        if !(echo "$management_ip" | grep -Eq '(^([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}$)|(^([[:xdigit:]]{0,4}:){2,7}[[:xdigit:]]{0,4}$)'); then
                            /usr/bin/dialog --msgbox "Management IP format incorrect" 8 60
                        elif !(echo "$internet_ip" | grep -Eq '(^([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}$)|(^([[:xdigit:]]{0,4}:){2,7}[[:xdigit:]]{0,4}$)'); then
                            /usr/bin/dialog --msgbox "Internet IP format incorrect" 8 60
                        elif  !(echo "$backends_outgoing_ip" | grep -Eq '(^([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}$)|(^([[:xdigit:]]{0,4}:){2,7}[[:xdigit:]]{0,4}$)'); then
                            /usr/bin/dialog --msgbox "Backends Outgoing IP format incorrect" 8 60
                        elif  !(echo "$logom_outgoing_ip" | grep -Eq '(^([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}$)|(^([[:xdigit:]]{0,4}:){2,7}[[:xdigit:]]{0,4}$)'); then
                            /usr/bin/dialog --msgbox "LogOM Outgoing IP format incorrect" 8 60
                        else
                            /usr/local/bin/sudo /home/vlt-adm/system/netconfig-resolv.sh
			    /usr/local/bin/sudo /home/vlt-adm/system/network-ips.sh "${management_ip}" "${internet_ip}" "${backends_outgoing_ip}" "${logom_outgoing_ip}"
                        fi
                    fi
                    ;;
                "update")
                    check_jails
                    /usr/local/bin/sudo /home/vlt-adm/system/update_system.sh
                    ;;
                "exit")
                    break
                    ;;
                "shell")
                    /bin/csh
                    ;;
                "rootshell")
                    /usr/local/bin/sudo /usr/bin/su
                    ;;
                "proxy")
                    /bin/rm -f "$tmp_file"
                    if [ -f /etc/rc.conf.proxy ]; then
                        proxy="$(/bin/cat /etc/rc.conf.proxy | /usr/bin/grep "http_" | /usr/bin/sed 's/.*http:\/\///')"
                    fi
                    if /usr/bin/dialog --title "Vulture HTTP Proxy setting" --inputbox "Enter HTTP proxy address (IPv4:port or [IPv6]:port)" 8 60 "${proxy}" --stdout > "$tmp_file"; then
                        proxy="$(/bin/cat "$tmp_file")"
                        /bin/rm "$tmp_file"

                        if  echo "$proxy" | grep -Eq '(^([[:digit:]]{1,3}\.){3}[[:digit:]]{1,3}:[[:digit:]]{1,5}$)|(^\[([[:xdigit:]]{0,4}:){2,7}[[:xdigit:]]{0,4}\]:[[:digit:]]{1,5}$)' || [ "$proxy" == "" ] ; then
                            /usr/local/bin/sudo /home/vlt-adm/system/proxy.sh "${proxy}"
                        else
                            /usr/bin/dialog --msgbox "IP format incorrect" 8 60
                        fi

                    fi
                    ;;
                "keymap")
                    /usr/local/bin/sudo /home/vlt-adm/system/keymap.sh
                    ;;
                "time")
                    /home/vlt-adm/system/time.sh
                    ;;
                "hostname")
                    check_jails

                    /usr/local/bin/sudo /home/vlt-adm/system/hostname.sh
                    ;;
                "netconfig")
                    /usr/local/bin/sudo /home/vlt-adm/system/netconfig.sh
                    ;;
            esac
            ;;
        "$DIALOG_CANCEL")
            /bin/echo "Cancel pressed."
            break
            ;;
        "$DIALOG_HELP")
            /bin/echo "Help pressed."
            /usr/bin/read a
            ;;
        "$DIALOG_EXTRA")
            /bin/echo "Extra button pressed."
            /usr/bin/read a
            ;;
        "$DIALOG_ITEM_HELP")
            /bin/echo "Item-help button pressed."
            /usr/bin/read a
            ;;
        "$DIALOG_ESC")
            /bin/echo "ESC pressed."
            /usr/bin/read a
            ;;
    esac

/bin/rm -rf "$tmp_file"

done
