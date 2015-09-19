:global number 0

:global maxIfCount 8

/interface wireless cap set enabled=no 
/interface wireless set country=switzerland [find] frequency-mode=regulatory-domain

/interface bridge 
	remove [find]
	add name=loopback auto-mac=no admin-mac=01:00:00:00:01:00
/interface ethernet
	 set master-port=none [find]

/routing ospf-v3 instance
	set [ find default=yes ] distribute-default=if-installed-as-type-1 router-id=(172.16.0.0+$number)


/interface bridge 
	remove [find]
	add name=loopback auto-mac=no admin-mac=01:00:00:00:01:00
	add name=wlan-client
/interface ethernet
	 set master-port=none [find]
/ipv6 address
	remove [find dynamic=no  ]
	add address=("fd58:9c23:3615::".$number."/128") advertise=no interface=loopback

/routing ospf-v3 interface
	remove [find]
	add area=backbone interface=loopback passive=yes

	:foreach interf in=[/interface ethernet find] do={
		add area=backbone interface=$interf
	}


/routing ospf instance
	set [ find default=yes ] distribute-default=if-installed-as-type-1 redistribute-connected=as-type-1 router-id=(172.16.0.0+$number)
/routing ospf network remove [find]
/interface gre6 remove [find]
{
	:local myWlanIp (10.0.0.1+$number*256*256)
	:local myWlanNet ((10.0.0.0+$number*256*256)."/16")
	/ip address 
		remove [find]
		add interface=wlan-client address=((10.0.0.1+$number*256*256)."/16")
	/ip pool
		remove [find]
		add name=wlan-client-pool ranges=((10.0.250.0+$number*256*256)."-".(10.0.255.255+$number*256*256))
	/ip dhcp-server 
		remove [find]
		add disabled=no interface=wlan-client name=dhcp-client-wlan address-pool=wlan-client-pool
	/ip dhcp-server network
		remove [find]
		add address=($myWlanNet."") dns-server=(10.0.0.1+$number*256*256) gateway=(10.0.0.1+$number*256*256)

}
/ip dhcp-server network
/ip dns
set allow-remote-requests=yes

/ip address add address=(172.16.0.0+$number) interface=loopback

{
	:local index 0
	:foreach interf in=[/interface ethernet find] do={
		:if ($index<$maxIfCount) do={
			:local ifname [/interface get value-name=name $interf]
			:local poolname ($ifname."-pool")
			:local dhcpname ("dhcp-".$ifname)
			:local ifNetIp [:toip (172.17.0.0+(16*($maxIfCount*$number+$index)))]
			/ip address remove [find dynamic=no interface=$ifname]
			/ip pool remove [find name=$poolname]
			/ip dhcp-server remove [find interface=$ifname]
			/ip dhcp-server network remove [find gateway=($ifNetIp+1)]

			:put (($ifNetIp+1)."/28")
			/ip address add address=(($ifNetIp+1)."/28") interface=$interf
			/ip pool add name=$poolname ranges=(($ifNetIp+2)."-".($ifNetIp+14))
			/ip dhcp-server add disabled=no interface=$ifname name=$dhcpname address-pool=$poolname
			/ip dhcp-server network add address=($ifNetIp."/28") dns-server=($ifNetIp+1) gateway=($ifNetIp+1)
		}
		:set $index ($index+1)
	}
}



/interface wireless cap set caps-man-addresses=fd58:9c23:3615::ffff enabled=yes interfaces=[/interface wireless find]

/caps-man channel
remove [find]
add band=2ghz-onlyn extension-channel=disabled frequency=2412 name=24-001
add band=2ghz-onlyn extension-channel=disabled frequency=2432 name=24-005
add band=2ghz-onlyn extension-channel=disabled frequency=2452 name=24-009
add band=2ghz-onlyn extension-channel=disabled frequency=2472 name=24-013
add band=5ghz-onlyn extension-channel=Ce frequency=5180 name=5-036
add band=5ghz-onlyn extension-channel=Ce frequency=5220 name=5-044
add band=5ghz-onlyn extension-channel=Ce frequency=5260 name=5-052
add band=5ghz-onlyn extension-channel=Ce frequency=5300 name=5-060
add band=5ghz-onlyac extension-channel=Ceee frequency=5500 name=5-100
add band=5ghz-onlyac extension-channel=Ceee frequency=5580 name=5-116


/system script
remove check-master
add name=check-master policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive source="{\
    \n    :local number $number\
    \n    :local masterCount 0\
    \n    :if (\$number>0) do={\
    \n        :for master from=0 to=(\$number-1) step=1 do={\
    \n            :local masterIP [:toip6 (\"fd58:9c23:3615::\".\$master)]\
    \n            :put \$master\
    \n            :set \$masterCount (\$masterCount+[:ping \$masterIP count=1])\
    \n        }\
    \n    }\
    \n    :local isMaster 0\
    \n    :foreach addr in=[/ipv6 address find where interface=loopback] do={\
    \n        :if ([/ipv6 address get \$addr address]=\"fd58:9c23:3615::ffff/128\") do={ :set \$isMaster \$addr }\
    \n    }\
    \n    :if (\$masterCount > 0) do={\
    \n        /ip dns set servers=fd58:9c23:3615::ffff\
    \n        /ip address remove [find where interface~\"^gre6-tunnel\"]\
    \n        /interface gre6 remove [find where name~\"^gre6-tunnel\"]\
    \n        :if (\$isMaster!=0) do={/ipv6 address remove \$isMaster}\
    \n        :foreach addr in=[/ipv6 address find where interface=loopback] do={\
    \n            if ([/ipv6 address get \$addr address]=\"fd58:9c23:3615::ffff/128\") do={\
    \n                /ipv6 address remove \$addr\
    \n            }\
    \n        }\
    \n        :if ([:len [/interface gre6 find where name=\"gre6-master-tunnel\"]]=0) do={\
    \n            /interface gre6 add local-address=(\"fd58:9c23:3615::\".\$number) remote-address=fd58:9c23:3615::ffff name=\"gre6-master-tunnel\"\
    \n            /ip address remove [find address=((172.16.1.2+(\$number-1)*4).\"/30\")]\
    \n            /ip address add address=((172.16.1.2+(\$number-1)*4).\"/30\") interface=gre6-master-tunnel\
    \n            /routing ospf network remove [find network=((172.16.1.0+(\$number-1)*4).\"/30\")]\
    \n            /routing ospf network add area=backbone network=((172.16.1.0+(\$number-1)*4).\"/30\")\
    \n        }\
    \n        /caps-man manager set enabled=no\
    \n    } else={\
    \n        /ip address remove [find address=((172.16.1.2+(\$number-1)*4).\"/30\")]\
    \n        /routing ospf network remove [find network=((172.16.1.0+(\$number-1)*4).\"/30\")]\
    \n        /interface gre6 remove [find where name=\"gre6-master-tunnel\"]\
    \n        :if (\$isMaster=0) do={\
    \n            /ipv6 address add address=fd58:9c23:3615::ffff/128 interface=loopback\
    \n            /caps-man radio provision [find where !interface]\
    \n        }\
    \n        /caps-man manager set enabled=yes\
    \n        :for tunnel from=0 to=20 step=1 do={\
    \n            :if (\$number != \$tunnel) do={\
    \n                :if ([:ping count=1 address=(\"fd58:9c23:3615::\".\$tunnel)]>0 && [:len [/interface gre6 find remote-address=(\"fd58:9c23:3615::\".\$tunnel)]]=0) do={\
    \n                    /interface gre6 add local-address=fd58:9c23:3615::ffff remote-address=(\"fd58:9c23:3615::\".\$tunnel) name=(\"gre6-tunnel\".\$tunnel)\
    \n                    /ip address remove [find address=((172.16.1.1+(\$tunnel-1)*4).\"/30\")]\
    \n                    /ip address add address=((172.16.1.1+(\$tunnel-1)*4).\"/30\") interface=(\"gre6-tunnel\".\$tunnel)\
    \n                    /routing ospf network remove [find network=((172.16.1.0+(\$tunnel-1)*4).\"/30\")]\
    \n                    /routing ospf network add area=backbone network=((172.16.1.0+(\$tunnel-1)*4).\"/30\")\
    \n                }\
    \n            }\
    \n        }\
    \n    }\
    \n}"


/system scheduler
	remove check-master
	add interval=1m name=check-master on-event="/system script run check-master"








