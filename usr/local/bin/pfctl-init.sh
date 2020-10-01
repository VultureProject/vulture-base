#!/bin/sh

# This script restores a default configuration for PF
management_ip="$(/bin/cat /usr/local/etc/management.ip)"
masquerading_ip="$(/bin/cat /usr/local/etc/masquerading.ip)"

grep ':' /usr/local/etc/management.ip > /dev/null
# IPV6 Management address
if [ "$?" == "0" ]; then
 JAILMANAGEMENT="fd00::20"
else
 JAILMANAGEMENT="127.0.0."
fi

grep ':' /usr/local/etc/masquerading.ip > /dev/null
# IPV6 Masquerading address
if [ "$?" == "0" ]; then
 JAILMASQUERADE="fd00::20"
else
 JAILMASQUERADE="127.0.0."
fi


MASQUERADING="nat pass proto udp from { ${JAILMASQUERADE}2,${JAILMASQUERADE}3,${JAILMASQUERADE}4,${JAILMASQUERADE}5,${JAILMASQUERADE}6,${JAILMASQUERADE}7 } to any port 53 -> ${masquerading_ip}  # jails -> DNS
nat pass proto tcp from { ${JAILMASQUERADE}2,${JAILMASQUERADE}3,${JAILMASQUERADE}4,${JAILMASQUERADE}5,${JAILMASQUERADE}6,${JAILMASQUERADE}7 } to any port 80 -> ${masquerading_ip}  # jails -> HTTP
nat pass proto tcp from { ${JAILMASQUERADE}2,${JAILMASQUERADE}3,${JAILMASQUERADE}4,${JAILMASQUERADE}5,${JAILMASQUERADE}6,${JAILMASQUERADE}7 } to any port 3128 -> ${masquerading_ip}  # jails -> Proxy
nat pass proto tcp from ${JAILMASQUERADE}6 to any port 443 -> ${masquerading_ip}  # vultureproject.org
nat pass proto tcp from ${JAILMANAGEMENT}6 to ${management_ip} port { 1978,6379,8000,9091 } -> ${management_ip}  # Haproxy, Redis, AdminGUI, Mongodb
nat pass proto tcp from ${JAILMANAGEMENT}7 to ${management_ip} port { 6379,9091 } -> ${management_ip}  # Redis, Mongodb
nat pass proto tcp from ${JAILMANAGEMENT}2 to !fd00::202 port 9091 -> ${management_ip}  # Mongodb
nat pass proto tcp from ${JAILMANAGEMENT}3 to any port 6379 -> ${management_ip}  # Redis
nat pass proto tcp from ${JAILMANAGEMENT}3 to any port 26379 -> ${management_ip}  # Sentinel
nat pass proto tcp from ${JAILMANAGEMENT}4 to ${management_ip} port 9091 -> ${management_ip}  # Rsyslog -> Mongodb
"
LOCAL_TO_JAIL="rdr pass proto tcp from ${management_ip} to ${management_ip} port 8000 -> ${JAILMANAGEMENT}6
rdr pass proto tcp from ${management_ip} to ${management_ip} port 1978 -> ${JAILMANAGEMENT}5
rdr pass proto tcp from any to ${management_ip} port 9091 -> ${JAILMANAGEMENT}2
rdr pass proto tcp from any to ${management_ip} port 6379 -> ${JAILMANAGEMENT}3
rdr pass proto tcp from any to ${management_ip} port 26379 -> ${JAILMANAGEMENT}3
"
REMOTE_TO_JAIL="rdr pass log proto tcp from any to ${management_ip} port { 8000 } -> ${JAILMANAGEMENT}6 port 8000
rdr pass log proto tcp from any to ${management_ip} port { 9091 } -> ${JAILMANAGEMENT}2 port 9091
rdr pass log proto tcp from any to ${management_ip} port { 6379 } -> ${JAILMANAGEMENT}3 port 6379
rdr pass log proto tcp from any to ${management_ip} port { 26379 } -> ${JAILMANAGEMENT}3 port 26379"
JAIL_INTERCONNECTION="pass quick proto tcp from ${JAILMANAGEMENT}5 to ${JAILMANAGEMENT}7 port 9000"


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
pass quick on lo1 all
pass quick on lo2 all
pass quick on lo3 all
pass quick on lo4 all
pass quick on lo5 all
pass quick on lo6 all
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
