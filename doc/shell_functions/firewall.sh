#!/bin/sh
# Generated by Firestarter 0.9.3, NETFILTER in use

# --------( Initial Setup - Variables (required) )--------

# Type of Service (TOS) parameters
# 8: Maximum Throughput - Minimum Delay
# 4: Minimize Delay - Maximize Reliability
# 16: No Delay - Moderate Throughput - High Reliability

TOSOPT=8

# Default Packet Rejection Type
# ( do NOT change this here - set it in the GUI instead )

# --------( Initial Setup - System Utilities Configuration )--------

IPT=/sbin/iptables
IFC=/sbin/ifconfig
MPB=/sbin/modprobe
LSM=/sbin/lsmod
RMM=/sbin/rmmod

# --------( Initial Setup - Network Information (required) )--------

IF=eth0
IP=`/sbin/ifconfig $IF | grep inet | cut -d : -f 2 | cut -d \  -f 1`
MASK=`/sbin/ifconfig $IF | grep Mas | cut -d : -f 4`
NET=$IP/$MASK

if [ "$MASK" = "" ]; then
	echo "External network device $IF is not ready. Aborting.."
	exit 2
fi

# --------( Initial Setup - Firewall Modules Check )--------

# Some distributions still load ipchains
$LSM | grep ipchains -q -s && $RMM ipchains

# --------( Initial Setup - Firewall Modules Autoloader )--------

if ! ( $LSM | /bin/grep ip_conntrack > /dev/null ); then
$MPB ip_conntrack
fi
if ! ( $LSM | /bin/grep ip_conntrack_ftp > /dev/null ); then
$MPB ip_conntrack_ftp
fi
if ! ( $LSM | /bin/grep ip_conntrack_irc > /dev/null ); then
$MPB ip_conntrack_irc
fi
if ! ( $LSM | /bin/grep ipt_REJECT > /dev/null ); then
$MPB ipt_REJECT
fi
if ! ( $LSM | /bin/grep ipt_REDIRECT > /dev/null ); then
$MPB ipt_REDIRECT
fi
if ! ( $LSM | /bin/grep ipt_TOS > /dev/null ); then
$MPB ipt_TOS
fi
if ! ( $LSM | /bin/grep ipt_MASQUERADE > /dev/null ); then
$MPB ipt_MASQUERADE
fi
if ! ( $LSM | /bin/grep ipt_LOG > /dev/null ); then
$MPB ipt_LOG
fi
if ! ( $LSM | /bin/grep iptable_mangle > /dev/null ); then
$MPB iptable_mangle
fi
if ! ( $LSM | /bin/grep iptable_nat > /dev/null ); then
$MPB iptable_nat
fi

if ! ( $LSM | /bin/grep ipt_ipv4optsstrip > /dev/null ); then
$MPB iptable_nat 2> /dev/null
fi

# --------( Chain Configuration - Flush Existing Chains )--------

# Purge standard chains (INPUT, OUTPUT, FORWARD).

$IPT -F
$IPT -X
$IPT -Z

# Purge extended chains (MANGLE & NAT) if they exist.

if ( $LSM | /bin/grep iptable_mangle > /dev/null ); then
$IPT -t mangle -F
$IPT -t mangle -X
$IPT -t mangle -Z
fi
if ( $LSM | /bin/grep iptable_nat > /dev/null ); then
$IPT -t nat -F
$IPT -t nat -X
$IPT -t nat -Z
fi

# Remove Firestarter lock
if [ -e /var/lock/subsys ]; then
  rm -f /var/lock/subsys/firestarter
else
  rm -f /var/lock/firestarter
fi

# --------( Chain Configuration - Configure Default Policy )--------

# Configure standard chains (INPUT, OUTPUT, FORWARD).

$IPT -P INPUT DROP
$IPT -P OUTPUT DROP
$IPT -P FORWARD DROP

# Configure extended chains (MANGLE & NAT) if required.

if ( $LSM | /bin/grep iptable_mangle > /dev/null ); then
$IPT -t mangle -P INPUT ACCEPT
$IPT -t mangle -P OUTPUT ACCEPT
$IPT -t mangle -P PREROUTING ACCEPT
$IPT -t mangle -P POSTROUTING ACCEPT
fi
if ( $LSM | /bin/grep iptable_nat > /dev/null ); then
$IPT -t nat -P OUTPUT ACCEPT
$IPT -t nat -P PREROUTING ACCEPT
$IPT -t nat -P POSTROUTING ACCEPT
fi

# --------( Chain Configuration - Create Default Result Chains )--------

# Create a new log and drop (LD) convenience chain.
$IPT -N LD 2> /dev/null
$IPT -F LD
$IPT -A LD -j LOG --log-level=info
$IPT -A LD -j DROP

STOP=LD

# --------( Chain Configuration - Create Default Traffic Chains )--------

# Create a new 'stateful module check' (STATE) convenience chain.
$IPT -N STATE 2> /dev/null
$IPT -F STATE
$IPT -I STATE -m state --state NEW -i ! lo -j $STOP
$IPT -A STATE -m state --state ESTABLISHED,RELATED -j ACCEPT
$IPT -A STATE -j $STOP

# Create a new 'sanity (check, mark and fwd) check' (SANITY) convenience chain.
$IPT -N SANITY 2> /dev/null
$IPT -F SANITY
$IPT -I SANITY -p tcp --tcp-flags SYN,ACK SYN,ACK -m state --state NEW -j REJECT --reject-with tcp-reset
$IPT -A SANITY -j $STOP

# --------( Initial Setup - Nameservers )--------

# Allow responses from the nameservers
while read keyword value garbage
	do
		if [ "$keyword" = "nameserver" ] ; then
			$IPT -A INPUT -p tcp ! --syn -s $value -d 0/0 -j ACCEPT
			$IPT -A INPUT -p udp -s $value -d 0/0 -j ACCEPT
		fi
	done < /etc/resolv.conf

# --------( User Defined Pre Script )--------

sh /etc/firestarter/user-pre

# --------( Initial Setup - External Lists )--------

# Trusted hosts
while read host garbage
	do
		$IPT -A INPUT -s $host -d 0/0 -j ACCEPT
	done < /etc/firestarter/trusted-hosts

# Blocked hosts
while read host garbage
	do
		$IPT -A INPUT -s $host -d 0/0 -j DROP
	done < /etc/firestarter/blocked-hosts

# Forwarded ports
while read port int_host int_port garbage
	do
		$IPT -A FORWARD -p tcp -d $int_host --dport $int_port -j ACCEPT
		$IPT -A FORWARD -p udp -d $int_host --dport $int_port -j ACCEPT
		$IPT -A PREROUTING -t nat -p tcp -d $NET --dport $port -j DNAT --to $int_host:$int_port
		$IPT -A PREROUTING -t nat -p udp -d $NET --dport $port -j DNAT --to $int_host:$int_port
	done < /etc/firestarter/forward

# Open ports
while read port garbage
	do
		$IPT -A INPUT -p tcp -s 0/0 -d $NET --dport $port -j ACCEPT
		$IPT -A INPUT -p udp -s 0/0 -d $NET --dport $port -j ACCEPT
	done < /etc/firestarter/open-ports

# Stealthed ports (Ports open to specific hosts)
while read port host garbage
	do
		$IPT -A INPUT -p tcp -s $host -d $NET --dport $port -j ACCEPT
		$IPT -A INPUT -p udp -s $host -d $NET --dport $port -j ACCEPT
	done < /etc/firestarter/stealthed-ports

# Blocked ports (explicit, no logging)
while read port garbage
	do
		$IPT -A INPUT -p tcp -s 0/0 -d 0/0 --dport $port -j DROP
		$IPT -A INPUT -p udp -s 0/0 -d 0/0 --dport $port -j DROP
	done < /etc/firestarter/blocked-ports

# --------( Sysctl Tuning - Recommended Parameters )--------

# Turn off IP forwarding by default
# (this will be enabled if you require masquerading)

if [ -e /proc/sys/net/ipv4/ip_forward ]; then
  echo 0 > /proc/sys/net/ipv4/ip_forward
fi

# Do not log 'odd' IP addresses (excludes 0.0.0.0 & 255.255.255.255)

if [ -e /proc/sys/net/ipv4/conf/all/log_martians ]; then
  echo 0 > /proc/sys/net/ipv4/conf/all/log_martians
fi

# --------( Sysctl Tuning - TCP Parameters )--------

# Turn off TCP Timestamping in kernel
if [ -e /proc/sys/net/ipv4/tcp_timestamps ]; then
  echo 0 > /proc/sys/net/ipv4/tcp_timestamps
fi

# Set TCP Re-Ordering value in kernel to '5'
if [ -e /proc/sys/net/ipv4/tcp_reordering ]; then
  echo 5 > /proc/sys/net/ipv4/tcp_reordering
fi

# Turn off TCP ACK in kernel
if [ -e /proc/sys/net/ipv4/tcp_sack ]; then
  echo 0 > /proc/sys/net/ipv4/tcp_sack
fi

#Turn off TCP Window Scaling in kernel
if [ -e /proc/sys/net/ipv4/tcp_window_scaling ]; then
  echo 0 > /proc/sys/net/ipv4/tcp_window_scaling
fi

#Set Keepalive timeout to 1800 seconds
if [ -e /proc/sys/net/ipv4/tcp_keepalive_time ]; then
  echo 1800 > /proc/sys/net/ipv4/tcp_keepalive_time
fi

#Set FIN timeout to 30 seconds
if [ -e /proc/sys/net/ipv4/tcp_fin_timeout ]; then
  echo 30 > /proc/sys/net/ipv4/tcp_fin_timeout
fi

# Set TCP retry count to 3
if [ -e /proc/sys/net/ipv4/tcp_retries1 ]; then
  echo 3 > /proc/sys/net/ipv4/tcp_retries1
fi

#Turn off ECN notification in kernel
if [ -e /proc/sys/net/ipv4/tcp_ecn ]; then
  echo 0 > /proc/sys/net/ipv4/tcp_ecn
fi

# --------( Sysctl Tuning - SYN Parameters )--------

# Turn on SYN cookies protection in kernel
if [ -e /proc/sys/net/ipv4/tcp_syncookies ]; then
  echo 1 > /proc/sys/net/ipv4/tcp_syncookies
fi

# Set SYN ACK retry attempts to '3'
if [ -e /proc/sys/net/ipv4/tcp_synack_retries ]; then
  echo 3 > /proc/sys/net/ipv4/tcp_synack_retries
fi

# Set SYN backlog buffer to '64'
if [ -e /proc/sys/net/ipv4/tcp_max_syn_backlog ]; then
  echo 64 > /proc/sys/net/ipv4/tcp_max_syn_backlog
fi

# Set SYN retry attempts to '6'
if [ -e /proc/sys/net/ipv4/tcp_syn_retries ]; then
  echo 6 > /proc/sys/net/ipv4/tcp_syn_retries
fi

# --------( Sysctl Tuning - Routing / Redirection Parameters )--------

# Turn on source address verification in kernel
if [ -e /proc/sys/net/ipv4/conf/all/rp_filter ]; then
  for f in /proc/sys/net/ipv4/conf/*/rp_filter
  do
   echo 1 > $f
  done
fi

# Turn off source routes in kernel
if [ -e /proc/sys/net/ipv4/conf/all/accept_source_route ]; then
  for f in /proc/sys/net/ipv4/conf/*/accept_source_route
  do
   echo 0 > $f
  done
fi

# Do not respond to 'redirected' packets
if [ -e /proc/sys/net/ipv4/secure_redirects ]; then
  echo 0 > /proc/sys/net/ipv4/secure_redirects
fi

# Do not reply to 'redirected' packets if requested
if [ -e /proc/sys/net/ipv4/send_redirects ]; then
  echo 0 > /proc/sys/net/ipv4/send_redirects
fi

# Do not reply to 'proxyarp' packets
if [ -e /proc/sys/net/ipv4/proxy_arp ]; then
  echo 0 > /proc/sys/net/ipv4/proxy_arp
fi

# Set FIB model to be RFC1812 Compliant
# (certain policy based routers may break with this - if you find
#  that you can't access certain hosts on your network - please set
#  this option to '0' - which is the default)

if [ -e /proc/sys/net/ipv4/ip_fib_model ]; then
  echo 2 > /proc/sys/net/ipv4/ip_fib_model
fi

# --------( Sysctl Tuning - ICMP/IGMP Parameters )--------

# ICMP Dead Error Messages protection
if [ -e /proc/sys/net/ipv4/icmp_ignore_bogus_error_responses ]; then
  echo 1 > /proc/sys/net/ipv4/icmp_ignore_bogus_error_responses
fi

# ICMP Broadcasting protection
if [ -e /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts ]; then
  echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts
fi

# IGMP Membership 'overflow' protection
# (if you are planning on running your box as a router - you should either
#  set this option to a number greater than 5, or disable this protection
#  altogether by commenting out this option)

if [ -e /proc/sys/net/ipv4/igmp_max_memberships ]; then
  echo 1 > /proc/sys/net/ipv4/igmp_max_memberships
fi

# --------( Sysctl Tuning - Miscellanous Parameters )--------

# Set TTL to '64' hops
# (If you are running a masqueraded network, or use policy-based
#  routing - you may want to increase this value depending on the load
#  on your link.)

if [ -e /proc/sys/net/ipv4/conf/all/ip_default_ttl ]; then
  for f in /proc/sys/net/ipv4/conf/*/ip_default_ttl
  do
   echo 64 > $f
  done
fi

# Always defragment incoming packets
# (Some cable modems [ Optus @home ] will suffer intermittent connection
#  droputs with this setting. If you experience problems, set this to '0')

if [ -e /proc/sys/net/ipv4/ip_always_defrag ]; then
  echo 1 > /proc/sys/net/ipv4/ip_always_defrag
fi

# Keep packet fragments in memory for 8 seconds
# (Note - this option has no affect if you turn packet defragmentation
#  (above) off!)

if [ -e /proc/sys/net/ipv4/ipfrag_time ]; then
  echo 8 > /proc/sys/net/ipv4/ipfrag_time
fi

# Do not reply to Address Mask Notification Warnings
# (If you are using your machine as a DMZ router or a PPP dialin server
#  that relies on proxy_arp requests to provide addresses to it's clients
#  you may wish to disable this option by setting the value to '1'

if [ -e /proc/sys/net/ipv4/ip_addrmask_agent ]; then
  echo 0 > /proc/sys/net/ipv4/ip_addrmask_agent
fi

# Turn off dynamic TCP/IP address hacking
# (Some broken PPPoE clients have issues when this is disabled
#  If you experience problems with DSL or Cable providers, set this to '1')

if [ -e /proc/sys/net/ipv4/ip_dynaddr ]; then
  echo 0 > /proc/sys/net/ipv4/ip_dynaddr
fi


# --------( Sysctl Tuning - IPTables Specific Parameters )--------

# Doubling current limit for ip_conntrack
if [ -e /proc/sys/net/ipv4/ip_conntrack_max ]; then
  echo 16384 > /proc/sys/net/ipv4/ip_conntrack_max
fi

# --------( Rules Configuration - Specific Rule - Loopback Interfaces )--------

# Allow all traffic on the loopback interface
$IPT -t filter -A INPUT -i lo -s 0/0 -d 0/0 -j ACCEPT
$IPT -t filter -A OUTPUT -o lo -s 0/0 -d 0/0 -j ACCEPT

# --------( Rules Configuration - Type of Service (ToS) - Ruleset Filtered by GUI )--------

# ToS: Client Applications
$IPT -t mangle -A OUTPUT -p tcp -j TOS --dport 20:21 --set-tos $TOSOPT
$IPT -t mangle -A OUTPUT -p tcp -j TOS --dport 22 --set-tos $TOSOPT
$IPT -t mangle -A OUTPUT -p tcp -j TOS --dport 68 --set-tos $TOSOPT
$IPT -t mangle -A OUTPUT -p tcp -j TOS --dport 80 --set-tos $TOSOPT
$IPT -t mangle -A OUTPUT -p tcp -j TOS --dport 443 --set-tos $TOSOPT


# --------( Rules Configuration - ICMP - Default Ruleset )--------

# Allowing all ICMP
$IPT -t filter -A INPUT -p icmp -s 0/0 -d $NET -m limit --limit 10/s -j ACCEPT


# --------( Rules Configuration - Inbound Traffic - Block nonroutable IP Addresses )--------

$IPT -N NR 2> /dev/null
$IPT -F NR
while read block garbage
	do
		$IPT -A NR -s $block -d $NET -i $IF -j $STOP
	done < /etc/firestarter/non-routables

$IPT -t filter -A INPUT -s ! $NET -i $IF -j NR

# --------( Rules Configuration - Inbound Traffic - Block known Trojan Ports )--------

#Block Back Orifice
$IPT -t filter -A INPUT -p tcp -s 0/0 -d $NET --dport 31337 -m limit --limit 2/minute -j $STOP
$IPT -t filter -A INPUT -p udp -s 0/0 -d $NET --dport 31337 -m limit --limit 2/minute -j $STOP

$IPT -t filter -A OUTPUT -p tcp -s $NET -d 0/0 --dport 31337 -m limit --limit 2/minute -j $STOP
$IPT -t filter -A OUTPUT -p udp -s $NET -d 0/0 --dport 31337 -m limit --limit 2/minute -j $STOP

#Block Trinity v3
$IPT -t filter -A INPUT -p tcp -s 0/0 -d $NET --dport 33270 -m limit --limit 2/minute -j $STOP
$IPT -t filter -A INPUT -p udp -s 0/0 -d $NET --dport 33270 -m limit --limit 2/minute -j $STOP

$IPT -t filter -A OUTPUT -p tcp -s $NET -d 0/0 --dport 33270 -m limit --limit 2/minute -j $STOP
$IPT -t filter -A OUTPUT -p udp -s $NET -d 0/0 --dport 33270 -m limit --limit 2/minute -j $STOP

#Block Subseven (1.7/1.9)
$IPT -t filter -A INPUT -p tcp -s 0/0 -d $NET --dport 1234 -m limit --limit 2/minute -j $STOP
$IPT -t filter -A INPUT -p tcp -s 0/0 -d $NET --dport 6711 -m limit --limit 2/minute -j $STOP

$IPT -t filter -A OUTPUT -p tcp -s $NET -d 0/0 --dport 1234 -m limit --limit 2/minute -j $STOP
$IPT -t filter -A OUTPUT -p tcp -s $NET -d 0/0 --dport 6711 -m limit --limit 2/minute -j $STOP

#Block Stacheldraht
$IPT -t filter -A INPUT -p tcp -s 0/0 -d $NET --dport 16660 --syn -m limit --limit 2/minute -j $STOP
$IPT -t filter -A INPUT -p tcp -s 0/0 -d $NET --dport 60001 --syn -m limit --limit 2/minute -j $STOP

$IPT -t filter -A OUTPUT -p tcp -s $NET -d 0/0 --dport 16660 --syn -m limit --limit 2/minute -j $STOP
$IPT -t filter -A OUTPUT -p tcp -s $NET -d 0/0 --dport 60001 --syn -m limit --limit 2/minute -j $STOP

#Block NetBus
$IPT -t filter -A INPUT -p tcp -s 0/0 -d $NET --dport 12345:12346 -m limit --limit 2/minute -j $STOP
$IPT -t filter -A INPUT -p udp -s 0/0 -d $NET --dport 12345:12346 -m limit --limit 2/minute -j $STOP

$IPT -t filter -A OUTPUT -p tcp -s $NET -d 0/0 --dport 12345:12346 -m limit --limit 2/minute -j $STOP
$IPT -t filter -A OUTPUT -p udp -s $NET -d 0/0 --dport 12345:12346 -m limit --limit 2/minute -j $STOP

#Block MS-RPC (dce)
$IPT -t filter -A INPUT -p tcp -s 0/0 -d $NET --dport 135 -m limit --limit 2/minute -j $STOP
$IPT -t filter -A INPUT -p udp -s 0/0 -d $NET --dport 135 -m limit --limit 2/minute -j $STOP

$IPT -t filter -A OUTPUT -p tcp -s $NET -d 0/0 --dport 135 -m limit --limit 2/minute -j $STOP
$IPT -t filter -A OUTPUT -p udp -s $NET -d 0/0 --dport 135 -m limit --limit 2/minute -j $STOP

#Block Trin00
$IPT -t filter -A INPUT -p tcp -s 0/0 -d $NET --dport 1524 -m limit --limit 2/minute -j $STOP
$IPT -t filter -A INPUT -p tcp -s 0/0 -d $NET --dport 27665 -m limit --limit 2/minute -j $STOP
$IPT -t filter -A INPUT -p udp -s 0/0 -d $NET --dport 27444 -m limit --limit 2/minute -j $STOP
$IPT -t filter -A INPUT -p udp -s 0/0 -d $NET --dport 31335 -m limit --limit 2/minute -j $STOP

$IPT -t filter -A OUTPUT -p tcp -s $NET -d 0/0 --dport 1524 -m limit --limit 2/minute -j $STOP
$IPT -t filter -A OUTPUT -p tcp -s $NET -d 0/0 --dport 27665 -m limit --limit 2/minute -j $STOP
$IPT -t filter -A OUTPUT -p udp -s $NET -d 0/0 --dport 27444 -m limit --limit 2/minute -j $STOP
$IPT -t filter -A OUTPUT -p udp -s $NET -d 0/0 --dport 31335 -m limit --limit 2/minute -j $STOP


# --------( Rules Configuration - Inbound Traffic - Block Multicast Traffic )--------

# (some cable/DSL providers require their clients to accept multicast transmissions
#  you should remove the following four rules if you are affected by multicasting
$IPT -t filter -A INPUT -s 224.0.0.0/8 -d 0/0 -j $STOP
$IPT -t filter -A INPUT -s 0/0 -d 224.0.0.0/8 -j $STOP
$IPT -t filter -A OUTPUT -s 224.0.0.0/8 -d 0/0 -j $STOP
$IPT -t filter -A OUTPUT -s 0/0 -d 224.0.0.0/8 -j $STOP


# --------( Rules Configuration - Inbound Traffic - Block Traffic w/ Stuffed Routing )--------

# (early versions of PUMP - (the DHCP client application included in RH / Mandrake) require
#  inbound packets to be accepted from a source address of 255.255.255.255.  If you have issues
#  with DHCP clients on your local LAN - either update PUMP, or remove the first rule below)
$IPT -t filter -A INPUT -s 255.255.255.255 -j $STOP
$IPT -t filter -A INPUT -d 0.0.0.0 -j $STOP
$IPT -t filter -A OUTPUT -s 255.255.255.255 -j $STOP
$IPT -t filter -A OUTPUT -d 0.0.0.0 -j $STOP


# --------( Rules Configuration - Inbound Traffic - Block Traffic w/ Invalid Flags )--------

$IPT -t filter -A INPUT -m state --state INVALID -j DROP


# --------( Rules Configuration - Inbound Traffic - Block Traffic w/ Excessive Fragmented Packets )--------

$IPT -t filter -A INPUT -f -m limit --limit 10/minute -j $STOP


# --------( Rules Configuration - Inbound Traffic - Ruleset Filtered by GUI )--------

#DHCP
$IPT -t filter -A INPUT -p tcp -s 0/0 -d 0/0 --dport 67:68 -i $IF -j ACCEPT

$IPT -t filter -A INPUT -p udp -s 0/0 -d 0/0 --dport 67:68 -i $IF -j ACCEPT

#FTP
$IPT -t filter -A INPUT -p tcp -s 0/0 -d $NET --dport 20  ! --syn -j ACCEPT
$IPT -t filter -A INPUT -p tcp -s 0/0 -d $NET --dport 21 -j ACCEPT

#SSH
$IPT -t filter -A INPUT -p tcp -s 0/0 -d $NET --dport 22 -j ACCEPT

#HTTP
$IPT -t filter -A INPUT -p tcp -s 0/0 -d $NET --dport 80 -j ACCEPT

#NTP
$IPT -t filter -A INPUT -p tcp -s 0/0 -d $NET --dport 123 -j ACCEPT
$IPT -t filter -A INPUT -p udp -s 0/0 -d $NET --dport 123 -j ACCEPT


# --------( Rules Configuration - Inbound Traffic - Highport Connection Fixes )--------

$IPT -A INPUT -p tcp ! --syn -m state --state NEW -j $STOP

#SSH fix
$IPT  -A INPUT -p tcp --sport 22 --dport 513:65535 ! --syn -m state --state RELATED -j ACCEPT

#FTP Data fix
$IPT  -A INPUT -p tcp --sport 20 --dport 1023:65535 ! --syn -m state --state RELATED -j ACCEPT


# --------( Rules Configuration - Inbound Traffic - Highport Connections )--------

$IPT  -A INPUT -p tcp -s 0/0 -d $NET --dport 1024:65535 -j STATE
$IPT  -A INPUT -p udp -s 0/0 -d $NET --dport 1023:65535 -j ACCEPT


# --------( Rules Configuration - Outbound Traffic - Highport Connection Fixes )--------

$IPT -A OUTPUT -p tcp ! --syn -m state --state NEW -j DROP


# --------( Rules Configuration - Outbound Traffic - Block Traffic w/ Invalid Flags )--------

$IPT -A OUTPUT -m state --state INVALID -j DROP

# --------( Rules Configuration - Outbound Traffic - TTL Mangling )--------

$IPT -A OUTPUT -m ttl --ttl 64


# --------( Rules Configuration - Outbound Traffic - Default Ruleset )--------

$IPT -A OUTPUT -p icmp -s $NET -d 0/0 -o $IF -j ACCEPT
$IPT -A OUTPUT -j ACCEPT


# --------( Catch all Rules (required) )--------

# Deny everything not let through earlier
$IPT -A INPUT -j $STOP

# --------( User Defined Post Script )--------

sh /etc/firestarter/user-post

# Create Firestarter lock file
if [ -e /var/lock/subsys ]; then
  touch /var/lock/subsys/firestarter
else
  touch /var/lock/firestarter
fi
