#!/bin/sh
#
#

# PROVIDE: vultured
# REQUIRE: jail
# BEFORE:  securelevel
# KEYWORD: shutdown

# Add the following line to /etc/rc.conf to enable `netdata':
#
# netdata_enable="YES"
#

. /etc/rc.subr

name="netdata"
rcvar=netdata_enable

load_rc_config $name

: ${netdata_enable="NO"}

#netdata_user="netdata"
pidfile="/var/run/netdata/netdata.pid"
procname="/usr/local/sbin/netdata"
command="/usr/sbin/daemon"
command_args="-f ${procname} -P ${pidfile} /usr/local/etc/netdata/netdata.conf"

run_rc_command "$1"