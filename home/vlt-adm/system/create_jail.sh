#! /bin/sh

if [ "$(/usr/bin/id -u)" != "0" ]; then
    /bin/echo "This script must be run as root" 1>&2
    exit 1
fi

temp_dir="/tmp"

pkg_url="http://pkg.vultureproject.org/"
vulture_conf="Vulture.conf"
pkg_ca="pkg.vultureproject.org"
update_url="http://updates.vultureproject.org/"
vulture_update_conf="hbsd-update.conf"
vulture_update_ca="ca.vultureproject.org"

template_folder="/usr/local/share/bastille-templates"

usage(){
    echo "Usage: create_jail jail_name"
}

update_repositories(){
    # Usage update_repositories [prefix_dir]
    prefix_dir=""
    if [ -n "$1" ]; then
        prefix_dir="$1"
    fi

    mkdir -p ${temp_dir}

    if [ ! -f ${temp_dir}/${vulture_conf} ]; then
        /bin/echo "[+] Downloading Vulture.conf"
        /usr/local/bin/wget ${pkg_url}${vulture_conf} --directory-prefix=${temp_dir} || finalize 1 "[/] Failed to download ${vulture_conf}"
        /bin/echo "[-] Done"
    fi

    /bin/echo "[+] Changing pkg repo to Vulture.conf"
    /bin/echo "Path: ${prefix_dir}/usr/local/etc/pkg/repos/*.conf"
    /bin/rm -f ${prefix_dir}/etc/pkg/*.conf ${prefix_dir}/usr/local/etc/pkg/repos/*.conf
    mkdir -p ${prefix_dir}/etc/pkg && /bin/cp ${temp_dir}/${vulture_conf} ${prefix_dir}/etc/pkg/${vulture_conf}
    mkdir -p ${prefix_dir}/usr/local/etc/pkg && /bin/cp ${temp_dir}/${vulture_conf} ${prefix_dir}/usr/local/etc/pkg/${vulture_conf}
    /bin/echo "[-] Done"

    if [ ! -f ${temp_dir}/${pkg_ca} ]; then
        /bin/echo "[+] Downloading $pkg_ca"
        /usr/local/bin/wget ${pkg_url}${pkg_ca} --directory-prefix=${temp_dir} || finalize 1 "[/] Failed to download $pkg_ca"
        /bin/echo "[-] Done"
    fi

    /bin/echo "[+] Saving $pkg_ca CA cert"
    /bin/rm -f  ${prefix_dir}/usr/share/keys/pkg/trusted/pkg.*
    mkdir -p ${prefix_dir}/usr/share/keys/pkg/trusted && /bin/cp ${temp_dir}/${pkg_ca}  ${prefix_dir}/usr/share/keys/pkg/trusted/${pkg_ca}
    /bin/echo "[-] Done"

    if [ ! -f ${temp_dir}/${vulture_update_conf} ]; then
        /bin/echo "[+] Downloading $vulture_update_conf"
        /usr/local/bin/wget ${update_url}${vulture_update_conf} --directory-prefix=${temp_dir} || finalize 1  "[/] Failed to download $vulture_update_conf"
        /bin/echo "[-] Done"
    fi

    /bin/echo "[+] Changing update repo to $vulture_update_conf"
    /bin/rm -f ${prefix_dir}/etc/hbsd-update.conf ${prefix_dir}/etc/hbsd-update.tor.conf
    mkdir -p ${prefix_dir}/etc && /bin/cp ${temp_dir}/${vulture_update_conf} ${prefix_dir}/etc/${vulture_update_conf}
    /bin/echo "[-] Done"

    if [ ! -f ${temp_dir}/${vulture_update_ca} ]; then
        /bin/echo "[+] Downloading $vulture_update_ca"
        /usr/local/bin/wget ${update_url}${vulture_update_ca} --directory-prefix=${temp_dir} || finalize 1  "[/] Failed to download $vulture_update_ca"
        /bin/echo "[-] Done"
    fi

    /bin/echo "[+] Saving $vulture_update_ca CA cert"
    /bin/rm -f ${prefix_dir}/usr/share/keys/hbsd-update/trusted/ca.hardenedbsd.org
    mkdir -p ${prefix_dir}/usr/share/keys/hbsd-update/trusted/ && /bin/cp ${temp_dir}/${vulture_update_ca} ${prefix_dir}/usr/share/keys/hbsd-update/trusted/${vulture_update_ca}
    /bin/echo "[-] Done"
}

start_services(){
    case "$jail" in
        rsyslog)
            output="$(/usr/sbin/jexec "$jail" /usr/sbin/service rsyslogd start 2>&1)"
            ;;
        mongodb)
            output="$(/usr/sbin/jexec "$jail" /usr/sbin/service mongod start 2>&1)"
            # TODO Force disable pageexec and mprotect on the mongo executable
            # there seems to be a bug currently with secadm when rules are pre-loaded on executables in packages
            # which is the case for latest mongodb36-3.6.23
            /usr/sbin/jexec "$jail" /usr/sbin/hbsdcontrol pax disable pageexec /usr/local/bin/mongo
            /usr/sbin/jexec "$jail" /usr/sbin/hbsdcontrol pax disable mprotect /usr/local/bin/mongo
            ;;
        redis)
            output="$(/usr/sbin/jexec "$jail" /usr/sbin/service redis start 2>&1)"
            output="$output
$(/usr/sbin/jexec "$jail" /usr/sbin/service sentinel start 2>&1)"
            ;;
        haproxy)
            output="$(/usr/sbin/jexec "$jail" /usr/sbin/service haproxy start 2>&1)"
            ;;
        apache)
            output="$(/usr/sbin/jexec "$jail" /usr/sbin/service nginx start 2>&1)"
            output="$output
$(/usr/sbin/jexec "$jail" /usr/sbin/service gunicorn start 2>&1)"
            ;;
        portal)
            output="$(/usr/sbin/jexec "$jail" /usr/sbin/service gunicorn start 2>&1)"
            ;;
    esac

    if echo "$output" | grep "ld-elf.so.1: Shared object \"libpython3.9.so.1.0\" not found" >> /dev/null; then
        bastille pkg "$jail" install -fy lang/python
        start_services
    fi
}

finalize() {
    # set default in case err_code is not specified
    err_code=$1
    err_message=$2
    # does not work with '${1:=0}' if $1 is not set...
    err_code=${err_code:=0}


    if [ -n "$err_message" ]; then
        echo ""
        echo "[!] ${err_message}"
        echo ""
    fi

    exit $err_code
}

if [ -n "$1" ]; then
    jail="$1"
else
    usage
    exit 1
fi

release="13-stable-BUILD-LATEST"

if zpool list -o name| grep "zroot" > /dev/null; then
    zpool="zroot"
elif zpool list -o name| grep "vulture" > /dev/null; then
    zpool="vulture"
fi

if [ ! -d "/usr/local/bastille/releases/13-stable-BUILD-LATEST" ]; then
    /bin/echo "[+] Bootstrapping $release"
    bastille bootstrap "$release" || finalize 1 "[/] Failed bootstrapping $release"
    update_repositories "/usr/local/bastille/releases/$release"
    /bin/echo "[-] Done bootstrapping $release"
fi

# create jails dataset because bastille ignores it if the directory exists, in this case /zroot
if [ -z "$(zfs list | grep ${zpool}/bastille/jails)" ]; then
    /bin/echo "[+] Creating ${zpool}/bastille/jails zfs dataset for jails"
    zfs create -o compress=lz4 -o atime=off -o mountpoint="/zroot" "${zpool}/bastille/jails" || finalize 1 "[/] Failed creating bastille jail zfs dataset $release"
fi

template_name="$jail"
case "$jail" in
    rsyslog)
        jail_ipv4="127.0.0.4"
        jail_ipv6="fd00::204"
        interface="lo3"
        ;;
    mongodb)
        jail_ipv4="127.0.0.2"
        jail_ipv6="fd00::202"
        interface="lo1"
        ;;
    redis)
        jail_ipv4="127.0.0.3"
        jail_ipv6="fd00::203"
        interface="lo2"
        ;;
    haproxy)
        jail_ipv4="127.0.0.5"
        jail_ipv6="fd00::205"
        interface="lo4"
        ;;
    apache)
        jail_ipv4="127.0.0.6/32"
        jail_ipv6="fd00::206"
        interface="lo5"
        template_name="gui"
        ;;
    portal)
        jail_ipv4="127.0.0.7/32"
        jail_ipv6="fd00::207"
        interface="lo6"
        ;;
esac

bastille create $jail "$release" "${jail_ipv4}" "$interface" || finalize 1 "[/] Failed creating bastille jail $jail"
# edit jail.conf
bastille config $jail set ip6                   # remove ipv6=disable
bastille config $jail set ip6.addr "$jail_ipv6"
bastille config $jail set allow.set_hostname 0
bastille config $jail set allow.raw_sockets 0
bastille config $jail set exec.system_user "root"
bastille config $jail set exec.jail_user "root"
bastille config $jail set allow.sysvipc 0
# Restart to apply changes
# TODO: Add error to null if it is ifconfig error with ipv6 on restart
bastille restart $jail

bastille template $jail $template_folder/vulture/$template_name --arg management_ip="$(/usr/sbin/sysrc -f /etc/rc.conf.d/network -n management_ip 2> /dev/null)" --arg hostname="$(hostname)" || finalize 1 "[/] Failed applying template to bastille jail $jail"

start_services

sysrc bastille_list+=$jail
/bin/echo "[-] Done creating bastille jail $jail"