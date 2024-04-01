#!/usr/bin/env bash

IP="/sbin/iptables-nft"
IP6="/sbin/ip6tables-nft"
IPS="/sbin/ipset"
NFT="/sbin/nft"
SC="/sbin/sysctl"

 "$IPS" flush script_blacklist
 "$IPS" destroy script_blacklist

 "$IPS" flush blacklist
 "$IPS" destroy blacklist
 "$IPS" create blacklist hash:ip family inet hashsize 43684 maxelem 900000000 timeout 60
 "$IPS" create script_blacklist hash:ip family inet hashsize 43684 maxelem 900000000
 
# Create a separate blacklist for the script to block IPs

urls=(
"https://iplists.firehol.org/files/sslproxies_30d.ipset"
"https://iplists.firehol.org/files/socks_proxy_30d.ipset"
)

declare -i ip_count=0

for url in "${urls[@]}"; do
    while IFS= read -r line; do
        if [[ ! $line =~ ^#.* ]]; then
            echo -ne "\rAdding $line to blacklist...";
            "${IPS}" add script_blacklist "$line"; # Add the IP to the script blacklist as well
            ((ip_count++))
        fi
    done < <(wget -qO- "$url")
done
echo -e "\nCompleted adding IPs to blacklist."
echo "Total number of IPs added: $ip_count"
# block the ips in the blacklist
"$IP" -I INPUT -j DROP -m set --match-set blacklist src
"$IP" -I OUTPUT -j DROP -m set --match-set blacklist src
"$IP" -I FORWARD -j DROP -m set --match-set blacklist src
# block the ips in the script blacklist
"$IP" -I INPUT -j DROP -m set --match-set script_blacklist src
"$IP" -I OUTPUT -j DROP -m set --match-set script_blacklist src
"$IP" -I FORWARD -j DROP -m set --match-set script_blacklist src
cat <<EOF > /etc/sysctl.conf
# /etc/sysctl.conf
net.netfilter.nf_conntrack_tcp_timeout_last_ack = 10
net.netfilter.nf_conntrack_tcp_timeout_close = 5
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 5
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 5
net.netfilter.nf_conntrack_tcp_timeout_syn_sent = 20
net.netfilter.nf_conntrack_tcp_timeout_syn_recv = 20
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 25
net.netfilter.nf_conntrack_tcp_timeout_established = 3600
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 1
net.ipv4.tcp_synack_retries = 2
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv4.conf.all.secure_redirects = 1
net.ipv6.conf.all.drop_unsolicited_na = 1
net.ipv6.conf.all.use_tempaddr = 2
net.ipv4.conf.all.drop_unicast_in_l2_multicast = 1
net.ipv6.conf.all.drop_unicast_in_l2_multicast = 1
net.ipv6.conf.default.dad_transmits = 0
net.ipv6.conf.default.autoconf = 0
net.ipv4.conf.all.drop_gratuitous_arp = 1
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.all.arp_filter = 1
kernel.sched_tunable_scaling = 1
kernel.shmmax = 268435456
vm.swappiness = 20
net.ipv4.tcp_window_scaling = 1
kernel.exec-shield = 1
net.ipv4.tcp_invalid_ratelimit = 500
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
EOF

/sbin/sysctl -p /etc/sysctl.conf > /dev/null 2>&1 &

