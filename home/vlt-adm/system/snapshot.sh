#!/usr/bin/env sh

COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW="\033[1;33m"
TEXT_BLINK='\033[5m'

#############
# variables #
#############
snap_name="AUTO_snapshot_$(date +%Y-%m-%dT%H:%M:%S)"
snap_system=0
snap_jails=0
snap_databases=0
snap_home=0
snap_tmpvar=0

SYSTEM_DATASETS="ROOT/$(/sbin/mount -l | /usr/bin/grep "on / " | /usr/bin/cut -d ' ' -f 1 | /usr/bin/cut -d / -f 3)"
ZPOOL="$(/sbin/mount -l | /usr/bin/grep "on / " | /usr/bin/cut -d / -f 1)"
JAIL_DATASETS="apache apache/var apache/usr portal portal/var portal/usr haproxy haproxy/var haproxy/usr mongodb mongodb/var mongodb/usr redis redis/var redis/usr rsyslog rsyslog/var rsyslog/usr"
DB_DATASETS="mongodb/var/db"
HOMES_DATASETS="usr/home"
TMPVAR_DATASETS="apache/var/log portal/var/log haproxy/var/log mongodb/var/log redis/var/log rsyslog/var/log tmp var/audit var/cache var/crash var/log var/tmp"
# 'usr' and 'var' are set to nomount, so they don't hold any data (data is held by the root dataset)

#############
# functions #
#############
. /usr/home/vlt-adm/system/common.sh

usage() {
    echo "USAGE ${0} OPTIONS"
    echo "OPTIONS:"
    echo "	-s	Snapshot the system dataset(s)"
    echo "	-j	Snapshot the jail(s) dataset(s)"
    echo "	-h	Snapshot the home dataset(s)"
    echo "	-d	Snapshot the databases dataset(s)"
    echo "	-t	Snapshot the tmp/var dataset(s)"
    exit 1
}

snapshot_datasets() {
    if [ -z "$1" ]; then
        warn "[!] No dataset provided, won't do anything"
        return 0
    fi

    for dataset in ${1}; do
        /sbin/zfs snap "${ZPOOL}/${dataset}@${snap_name}"
    done
}

snapshot_system() {
    snapshot_datasets "$SYSTEM_DATASETS"
}

snapshot_jails() {
    snapshot_datasets "$JAIL_DATASETS"
}

snapshot_databases() {
    snapshot_datasets "$DB_DATASETS"
}

snapshot_homes() {
    snapshot_datasets "$HOMES_DATASETS"
}

snapshot_tmpvar() {
    snapshot_datasets "$TMPVAR_DATASETS"
}


if [ "$(/usr/bin/id -u)" != "0" ]; then
    error "[!] This script must be run as root"
    exit 1
fi

while getopts 'sjdht' opt; do
    case "${opt}" in
        s)  snap_system=1;
            ;;
        j)  snap_jails=1;
            ;;
        d)  snap_databases=1;
            ;;
        h)  snap_home=1;
            ;;
        t)  snap_tmpvar=1;
            ;;
        *)  usage;
            ;;
    esac
done
shift $((OPTIND-1))

if [ $snap_system -gt 0 ]; then 
    echo "snapshotting system"
    snapshot_system
fi
if [ $snap_jails -gt 0 ]; then 
    echo "snapshotting jails"
    snapshot_jails
fi
if [ $snap_databases -gt 0 ]; then 
    echo "snapshotting databases"
    snapshot_databases
fi
if [ $snap_home -gt 0 ]; then 
    echo "snapshotting home"
    snapshot_homes
fi
if [ $snap_tmpvar -gt 0 ]; then 
    echo "snapshotting tmpvar"
    snapshot_tmpvar
fi
