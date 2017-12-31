#!/bin/bash

export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin

clear
#Define some color to has a nice prompt
red='\033[31m'
plain='\033[0m'
blue='\033[36m'
green='\033[42m'
echo -e "${green}###################################################################${plain}"
echo -e "${green}#                         Happy Coding                            #${plain}"
echo -e "${green}# MyGithub: https//github.com/Happy4Code/ShadowSocksInstallScript #${plain}"
echo -e "${green}# Author:   NoOne                                                 #${plain}"
echo -e "${green}###################################################################${plain}"

#First to check the user ID
if [ $EUID -ne 0 ];then
  echo -e "[${red}ERROR${plain}] Please change to root then run this script" && exit 1
fi

curDir=`pwd`

#In order to avoid the problem caused by selinux, close it
closeSelinux(){
  if [ -f /etc/selinux/config ];then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    setenforce 0
  fi
}

#Get the public IP information about your server
ipInfo(){
 #Search for the public IP of your machine
 [ -z ${IP} ] && IP=$(wget -qO- -t1 -T2 ipv4.icanhazip.com); 
 [ -z ${IP} ] && IP=$(wget -qO- -t1 -T2 ipinfo.io/ip)
 [ ! -z ${IP} ] && echo ${IP}
 #If we can't get the server Ip address
 if [ -z ${IP} ];then
 	 read -p "We can't get your server IP address, please enter your Ip address: " IP
   [ ! -z ${IP} ] && echo ${IP}
 fi
}

#Check system stuff
checkSystemStuff(){
  local packageManager=""
  local systemDistribution=""
  
  if [ -f /etc/redhat-release ];then
    packageManager="yum"
    systemDistribution="centos"
  elif lsb_release -a | grep -Eqi "CentOS";then
    packageManager="yum"
    systemDistribution="centos"
  elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    packageManager="yum"
    systemDistribution="centos"
  else
    echo -e "[${red}ERROR${plain}]The script only support centos or red-hat distribution" && exit 1
  fi
}

#Get the version of your centos
checkVersion(){
 if [ -s /etc/redhat-release ];then
   local version=$(grep -oE "[0-9.]+" /etc/redhat-release)
   MainVersion=${version%%.*}
   #If this version is less than 5, the script is not working well
   if [ "$MainVersion" == "5" ]; then
     echo -e "[${red}ERROR${plain}]The script only support version 6 or higher " && exit 1
   fi  
 fi  
}
#Pre-Install
preInstall(){
  yum update
  yum install -y make gcc gmp-devel xmlto bison flex xmlto libpcap-devel lsof vim-enhanced man iptables 
}

#Install Openswan
installOpenswan(){
  yum install -y openswan
}

#Config IPSEC
configIPSEC(){
	cat  > /etc/ipsec.conf<<-EOF
config setup
    nat_traversal=yes
    virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12
    oe=off
    protostack=netkey

conn L2TP-PSK-NAT
    rightsubnet=vhost:%priv
    also=L2TP-PSK-noNAT

conn L2TP-PSK-noNAT
    authby=secret
    pfs=no
    auto=add
    keyingtries=3
    rekey=no
    ikelifetime=8h
    keylife=1h
    type=transport
    left=$(ipInfo)
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
EOF

echo -e "[${blue}INFO${plain}]Please input your PSK"
read -p "Your PSK[Default noone]:" PSK

[ -z "${PSK}" ] && PSK="noone"

cat >/etc/ipsec.secrets<<-EOF
$(ipInfo) %any: PSK "${PSK}"
EOF
}

#Install ppp
installPPP(){
  yum -y install ppp
}

#Config PPP
configPPP(){
echo -e "[${blue}INFO${plain}]Please input your username"
read -p "Your username[Default noone]:" username
[ -z "${username}" ] && username="noone"

echo -e "[${blue}INFO${plain}]Please input your password"
read -p "Your password[Default noone]:" password
[ -z "${password}" ] && password="noonepwd"


  cat >/etc/ppp/chap-secrets<<-EOF
# Secrets for authentication using CHAP
# client    server  secret          IP addresses
${username}      *  ${password}     *
EOF
}

#Install xl2tpd
installxl2tpd(){
  if [ "${MainVersion}" == "6" ];then
  rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm
  echo -e [${green}INFO${plain}]Downlaod the 6th version of xl2tpd
  elif [ "${MainVersion}" == "7" ];then
  rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
  echo -e [${green}INFO${plain}]Downlaod the 7th version of xl2tpd
  fi
  
  yum -y install xl2tpd
}

#Config the xl2tp
configxl2tp(){
	cat > /etc/xl2tpd/xl2tpd.conf<<-EOF
[global]
ipsec saref = yes
listen-addr = $(ipInfo)
port=1701
[lns default]
ip range = 192.168.1.2-192.168.1.100
local ip = 192.168.1.1
refuse chap = yes
refuse pap = yes
require authentication = yes
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

#Config the ppp component work together with xl2tpd
	cat > /etc/ppp/options.xl2tpd<<-EOF
require-mschap-v2
ms-dns 8.8.8.8
ms-dns 8.8.4.4
asyncmap 0
auth
crtscts
lock
hide-password
modem
debug
name l2tpd
proxyarp
lcp-echo-interval 30
lcp-echo-failure 4
EOF

}

#Config Network option
configNetwork(){
    cp -pf /etc/sysctl.conf /etc/sysctl.conf.bak
	grep 'net.ipv4.ip_forward' /etc/sysctl.conf
     
    if [ $? -eq 0 ];then
      sed -i 's/net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/g' /etc/sysctl.conf
    else
      echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    fi
     
    echo "net.ipv4.tcp_syncookies=1" >> /etc/sysctl.conf
    echo "net.ipv4.icmp_echo_ignore_broadcasts=1" >> /etc/sysctl.conf
    echo "net.ipv4.icmp_ignore_bogus_error_responses=1" >> /etc/sysctl.conf

    for each in `ls /proc/sys/net/ipv4/conf/`; do
        echo "net.ipv4.conf.${each}.accept_source_route=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.accept_redirects=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.send_redirects=0" >> /etc/sysctl.conf
        echo "net.ipv4.conf.${each}.rp_filter=0" >> /etc/sysctl.conf
    done
    sysctl -p
}
firewallConfig(){
	iptables -A INPUT -m policy --dir in --pol ipsec -j ACCEPT
	iptables -A FORWARD -m policy --dir in --pol ipsec -j ACCEPT
	iptables -t nat -A POSTROUTING -m policy --dir out --pol none -j MASQUERADE
	iptables -A FORWARD -i ppp+ -p all -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
	iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
	iptables -A INPUT -m policy --dir in --pol ipsec -p udp --dport 1701 -j ACCEPT
	iptables -A INPUT -p udp --dport 500 -j ACCEPT
	iptables -A INPUT -p udp --dport 4500 -j ACCEPT
	iptables -t nat -A POSTROUTING -s 192.168.1.0/24 -o eth0 -j MASQUERADE

	service iptables save
	service iptables restart
}


#Run these software
run(){
    sed -i '/ExecStartPre/s/^/#/' /usr/lib/systemd/system/xl2tpd.service
    systemctl daemon-reload
	service ipsec restart
	chkconfig ipsec on
	service xl2tpd restart 
	chkconfig xl2tpd on
    ipsec verify
}
#Print UserInfo
printInfo(){
    clear
	echo    "########################################################"
	echo -e "[${blue}Ip${plain}]:      $(ipInfo)                   "
	echo -e "[${blue}Username${plain}]:${username}                 "
	echo -e "[${blue}Password${plain}]:${password}                 "
	echo -e "[${blue}PSK${plain}]:     ${PSK}                      "
	echo -e "[${blue}port${plain}]:    1701                        "
	echo    "########################################################"
}

#install and run
installAndRun(){
	closeSelinux
    checkSystemStuff
	checkVersion
    preInstall
	
    installOpenswan
    configIPSEC
    installPPP
    configPPP

    installxl2tpd
    configxl2tpd
    configNetwork
	firewallConfig
	run
	printInfo
}

installAndRun


