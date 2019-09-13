#!/bin/sh

#This script restores a default configuration for PF
management_ip="$(/bin/cat /usr/local/etc/management.ip)"

grep ':' /usr/local/etc/management.ip > /dev/null
#IPV6 Management address
if [ "$?" == "0" ]; then
    MASQUERADING="nat pass proto udp from { fd00::202,fd00::203,fd00::204,fd00::205,fd00::206,fd00::207 } to any port 53 -> ${management_ip}  # jails -> DNS
nat pass proto tcp from { fd00::202,fd00::203,fd00::204,fd00::205,fd00::206,fd00::207 } to any port 80 -> ${management_ip}  # jails -> HTTP
nat pass proto tcp from { fd00::202,fd00::203,fd00::204,fd00::205,fd00::206,fd00::207 } to any port 3128 -> ${management_ip}  # jails -> Proxy
nat pass proto tcp from fd00::206 to any port 443 -> ${management_ip}  # vultureproject.org
nat pass proto tcp from fd00::206 to ${management_ip} port { 1978,4200,6379,8000,9091,19999 } -> ${management_ip}  # Haproxy, hellInaBox, Redis, AdminGUI, Mongodb, Netdata
nat pass proto tcp from fd00::207 to ${management_ip} port { 6379,9091 } -> ${management_ip}  # Redis, Mongodb
nat pass proto tcp from fd00::202 to any port 9091 -> ${management_ip}  # Mongodb
nat pass proto tcp from fd00::203 to any port 6379 -> ${management_ip}  # Redis
nat pass proto tcp from fd00::203 to any port 26379 -> ${management_ip}  # Sentinel
nat pass proto tcp from fd00::204 to ${management_ip} port 9091 -> ${management_ip}  # Rsyslog -> Mongodb
"
    LOCAL_TO_JAIL="rdr pass proto tcp from ${management_ip} to ${management_ip} port 8000 -> fd00::206
rdr pass proto tcp from ${management_ip} to ${management_ip} port 19999 -> ::1
rdr pass proto tcp from ${management_ip} to ${management_ip} port 1978 -> fd00::205
rdr pass proto tcp from ${management_ip} to ${management_ip} port 4200 -> ::1 #Fixme: shellinabox listens on 127.0.0.1
rdr pass proto tcp from any to ${management_ip} port 9091 -> fd00::202
rdr pass proto tcp from any to ${management_ip} port 6379 -> fd00::203
rdr pass proto tcp from any to ${management_ip} port 26379 -> fd00::203
"
    REMOTE_TO_JAIL="rdr pass log proto tcp from any to ${management_ip} port { 8000 } -> fd00::206 port 8000"
    JAIL_INTERCONNECTION="pass quick proto tcp from fd00::205 to fd00::207 port 9000"
else
    MASQUERADING="nat pass proto udp from { 127.0.0.2,127.0.0.3,127.0.0.4,127.0.0.5,127.0.0.6,127.0.0.7 } to any port 53 -> ${management_ip}  # jails -> DNS
nat pass proto tcp from { 127.0.0.2,127.0.0.3,127.0.0.4,127.0.0.5,127.0.0.6,127.0.0.7 } to any port 80 -> ${management_ip}  # jails -> HTTP
nat pass proto tcp from { 127.0.0.2,127.0.0.3,127.0.0.4,127.0.0.5,127.0.0.6,127.0.0.7 } to any port 3128 -> ${management_ip}  # jails -> HTTP
nat pass proto tcp from 127.0.0.6 to any port 443 -> ${management_ip}  # Apache jail -> vultureproject.org
nat pass proto tcp from 127.0.0.6 to any port { 1978,4200,6379,8000,9091,19999 } -> ${management_ip}   # Haproxy, ShellInaBox, Redis, AdminGUI, Mongodb, Netdata
nat pass proto tcp from 127.0.0.7 to ${management_ip} port { 6379,9091 } -> ${management_ip}   # Redis, Mongodb
nat pass proto tcp from 127.0.0.2 to any port 9091 -> ${management_ip}  # Mongodb
nat pass proto tcp from 127.0.0.3 to any port 6379 -> ${management_ip}  # Redis
nat pass proto tcp from 127.0.0.3 to any port 26379 -> ${management_ip}  # Sentinel
nat pass proto tcp from 127.0.0.4 to ${management_ip} port 9091 -> ${management_ip}  # Rsyslog -> Mongodb
"
    LOCAL_TO_JAIL="rdr pass proto tcp from ${management_ip} to ${management_ip} port 8000 -> 127.0.0.6
rdr pass proto tcp from ${management_ip} to ${management_ip} port 19999 -> 127.0.0.1
rdr pass proto tcp from ${management_ip} to ${management_ip} port 1978 -> 127.0.0.5
rdr pass proto tcp from ${management_ip} to ${management_ip} port 4200 -> 127.0.0.1
rdr pass proto tcp from any to ${management_ip} port 9091 -> 127.0.0.2
rdr pass proto tcp from any to ${management_ip} port 6379 -> 127.0.0.3
rdr pass proto tcp from any to ${management_ip} port 26379 -> 127.0.0.3
"
    REMOTE_TO_JAIL="rdr pass log proto tcp from any to ${management_ip} port { 8000 } -> 127.0.0.6 port 8000
rdr pass log proto tcp from any to ${management_ip} port { 9091 } -> 127.0.0.2 port 9091
rdr pass log proto tcp from any to ${management_ip} port { 6379 } -> 127.0.0.3 port 6379
rdr pass log proto tcp from any to ${management_ip} port { 26379 } -> 127.0.0.3 port 26379"

    JAIL_INTERCONNECTION="pass quick proto tcp from 127.0.0.5 to 127.0.0.7 port 9000"
fi

/bin/echo "# BOOTSTRAP FIREWALL CONFIG
# THIS WILL BE ERASED BY VULTURE-OS LATER

scrub in all

#Jails Masquerading
${MASQUERADING}

#Local communication to Jails
${LOCAL_TO_JAIL}

#Remote communication to jails (only for GUI)
${REMOTE_TO_JAIL}

#######################

# Generic directives
pass quick on lo0 all
block in log all
#pass in proto icmp6 all
#pass out proto icmp6 all
# ICMP6
# Packet too big (type 2)
# Neighbor Discovery Protocol (NDP) (types 133-137):
#   Router Solicitation (RS), Router Advertisement (RA)
#   Neighbor Solicitation (NS), Neighbor Advertisement (NA)
#   Route Redirection
pass in quick inet6 proto ipv6-icmp icmp6-type { 2, 133, 134, 135, 136, 137 } keep state
pass out all keep state
####################

# ---- Allow SSH for remote administration
pass log quick proto tcp from any to any port 22 flags S/SA keep state \
 (max-src-conn 10, max-src-conn-rate 3/5, overload <vulture_blacklist> flush global)
#########################

# Jails interconnections
${JAIL_INTERCONNECTION}
#########################

" > /usr/local/etc/pf.conf