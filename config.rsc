/system package enable ipv6 
/system package enable wireless

:global number
:if ([:len [/ip address find where interface=loopback]] > 0) do={
	:local loopbackip [/ip address get value-name=address [/ip address find where interface=loopback]]
	:set number ([:toip [:pick $loopbackip 0 [:find $loopbackip "/"]]]-172.16.0.0)
} else={
	:if ($number < 1) do={
		:error "no loopback found"
	}
}
:put ("Number: ".$number)

:global maxIfCount 20
:global v6prefix "fd7e:907d:34ab"
#:global v6prefix "fd58:9c23:3615"

/interface wireless cap set enabled=no 
:if ([:len [/interface wireless find]]>0) do={
	/interface wireless set country=switzerland [find] frequency-mode=regulatory-domain
}
/certificate
	remove [find]

/interface ethernet
#	 set master-port=none [find]
:put "setup ospfv3"
/routing ospf-v3 instance
	remove [find default=no]
	set [ find default=yes ] distribute-default=never router-id=(172.16.0.0+$number)

:put "create loopback"
/interface bridge 
	remove [find name=loopback]
	remove [find name=wlan-client]
	add name=loopback auto-mac=no admin-mac=01:00:00:00:01:00
	add name=wlan-client
/ipv6 address
	remove [find dynamic=no  ]
	add address=($v6prefix."::".$number."/128") advertise=no interface=loopback
/ip address 
	remove [find]
	add address=(172.16.0.0+$number."/32") interface=loopback

/routing ospf-v3 interface
	remove [find]
	add area=backbone interface=loopback passive=yes

	:foreach interf in=[/interface ethernet find master-port=none] do={
		add area=backbone interface=$interf
	}


:put "setup ospf"
/routing ospf instance
	set [ find default=yes ] distribute-default=if-installed-as-type-1 redistribute-connected=as-type-1 router-id=(172.16.0.0+$number)
/routing ospf network 
	remove [find]
	add area=backbone network=((10.0.0.0+$number*256*256)."/16")
	add area=backbone network=((172.16.0.0+$number)."/32")

:put "cleanup gre6 and eoipv6"
/interface gre6 remove [find]
/interface eoipv6 remove [find]
:put "setup wlan"
{
	:local myWlanIp (10.0.252.1+$number*256*256)
	:local myWlanNet ((10.0.252.0+$number*256*256)."/22")
	/ip address 
		add interface=wlan-client address=((10.0.252.1+$number*256*256)."/22")
	/ip pool
		remove [find]
		add name=wlan-client-pool ranges=((10.0.253.0+$number*256*256)."-".(10.0.255.254+$number*256*256))
	/ip dhcp-server 
		remove [find]
		add disabled=no interface=wlan-client name=dhcp-client-wlan address-pool=wlan-client-pool
	/ip dhcp-server network
		remove [find]
		add address=($myWlanNet."") dns-server=(10.0.252.1+$number*256*256) gateway=(10.0.252.1+$number*256*256)

}
:put "setup dns"
/ip dns
	set allow-remote-requests=yes servers=($v6prefix."::fffe,172.16.255.1")
	static remove [find where address=($v6prefix."::".$number)]
	static add address=($v6prefix."::".$number) name=("station-".$number.".lan")


:put "setup ethernet interfaces"
/ip dhcp-client remove [find where add-default-route=no]
{
	:local index 0
	:foreach interf in=[/interface ethernet find where !slave] do={
		:if ($index<$maxIfCount) do={
			:local ifname [/interface get value-name=name $interf]
			:local poolname ($ifname."-pool")
			:local dhcpname ("dhcp-".$ifname)
			:local ifNetIp [:toip (10.0.0.0+(256*(256*$number+$index)))]
			/ip address remove [find dynamic=no interface=$ifname]
			/ip pool remove [find name=$poolname]
			/ip dhcp-server remove [find interface=$ifname]
			/ip dhcp-server network remove [find gateway=($ifNetIp+1)]

			:put (($ifNetIp+1)."/24")
			/ip address add address=(($ifNetIp+1)."/24") interface=$interf
			/ip pool add name=$poolname ranges=(($ifNetIp+50)."-".($ifNetIp+254))
			/ip dhcp-server add disabled=no interface=$ifname name=$dhcpname address-pool=$poolname
			/ip dhcp-server network add address=($ifNetIp."/24") dns-server=($ifNetIp+1) gateway=($ifNetIp+1)
		}
		:set $index ($index+1)
	}
}


:put "setup perdiodical update"
/system script
remove [find name=check-master]
add name=check-master owner=admin policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive source=("{\
    \n    :global loopbackip [/ip address get value-name=address [/ip address find where interface=loopback]]\
    \n    :global number ([:toip [:pick \$loopbackip 0 [:find \$loopbackip \"/\"]]]-172.16.0.0)\
    \n    :global v6prefix \"".$v6prefix."\"\
    \n    :local masterCount 0\
    \n    :if (\$number>0) do={\
    \n        :for master from=0 to=(\$number-1) step=1 do={\
    \n            :local masterIP (\$v6prefix.\"::\".\$master.\"/128\")\
    \n            #:put \$master\
    \n            :set \$masterCount (\$masterCount+[:len [/ipv6 route find where dst-address=\$masterIP]])\
    \n        }\
    \n    }\
    \n    :local isMaster 0\
    \n    :foreach addr in=[/ipv6 address find where interface=loopback] do={\
    \n        :if ([/ipv6 address get \$addr address]=(\$v6prefix.\"::ffff/128\")) do={ :set \$isMaster \$addr }\
    \n    }\
    \n    :if (\$masterCount > 0) do={\
    \n        #/ip dns set servers=(\$v6prefix.\"::fffe\")\
    \n        /ip address remove [find where interface~\"^gre6-tunnel\"]\
    \n        #/ipv6 dhcp-client remove [find where interface=gre6-master-tunnel]\
    \n        /interface gre6 remove [find where name~\"^gre6-tunnel\"]\
    \n        /interface eoipv6 remove [find where name~\"^eoipv6-tunnel\"]\
    \n        :if (\$isMaster!=0) do={/ipv6 address remove \$isMaster}\
    \n        :foreach addr in=[/ipv6 address find where interface=loopback] do={\
    \n            :if ([/ipv6 address get \$addr address]=(\$v6prefix.\"::ffff/128\")) do={\
    \n                /ipv6 address remove \$addr\
    \n            }\
    \n        }\
    \n        :if ([:len [/interface eoipv6 find where name=\"eoipv6-master-tunnel\"]]=0) do={\
    \n            /interface gre6 add local-address=(\$v6prefix.\"::\".\$number) remote-address=(\$v6prefix.\"::ffff\") name=\"gre6-master-tunnel\"\
    \n            /interface eoipv6 add local-address=(\$v6prefix.\"::\".\$number) remote-address=(\$v6prefix.\"::ffff\") name=\"eoipv6-master-tunnel\" tunnel-id=\$number\
    \n            /ip address remove [find address=((172.16.1.2+(\$number-1)*4).\"/30\")]\
    \n            #/ip address add address=((172.16.1.2+(\$number-1)*4).\"/30\") interface=gre6-master-tunnel\
    \n            #/routing ospf network remove [find network=((172.16.1.0+(\$number-1)*4).\"/30\")]\
    \n            #/routing ospf network add area=backbone network=((172.16.1.0+(\$number-1)*4).\"/30\")\
    \n            /interface wireless cap set caps-man-addresses=\"\" discovery-interfaces=eoipv6-master-tunnel enabled=yes interfaces=[/interface wireless find where interface-type!=virtual] certificate=none\
    \n            /ipv6 dhcp-client add interface=gre6-master-tunnel pool-name=local-v6-pool pool-prefix-length=60 use-peer-dns=no\
    \n        }\
    \n        /ipv6 address set from-pool=local-v6-pool [/ipv6 address find from-pool=public-pool]\
    \n        /caps-man manager set enabled=no\
    \n    } else={\
    \n        /ip address remove [find address=((172.16.1.2+(\$number-1)*4).\"/30\")]\
    \n        #/routing ospf network remove [find network=((172.16.1.0+(\$number-1)*4).\"/30\")]\
    \n        /interface gre6 remove [find where name=\"gre6-master-tunnel\"]\
    \n        /interface eoipv6 remove [find where name=\"eoipv6-master-tunnel\"]\
    \n        :if (\$isMaster=0) do={\
    \n            /ipv6 address add address=(\$v6prefix.\"::ffff/128\") interface=loopback\
    \n            /caps-man radio provision [find where !interface]\
    \n            /caps-man manager set enabled=yes\
    \n            /interface wireless cap set discovery-interfaces=loopback\
    \n        }\
    \n        :for tunnel from=0 to=100 step=1 do={\
    \n            #:put (\"Tunnel: \".\$tunnel)\
    \n            :if (\$number != \$tunnel) do={\
    \n                :local tunnelPrefix (\$v6prefix.\"::\".\$tunnel.\"/128\")\
    \n                :local tunnelIP (\$v6prefix.\"::\".\$tunnel)\
    \n                #:put (\"Check : \".\$tunnelIP)\
    \n                :if ([:len [/ipv6 route find where dst-address=\$tunnelPrefix]]>0) do={\
    \n                    #:put (\"Found: \".\$tunnel)
    \n                    :if ([:len [/ip dns static find where name=(\"station-\".\$tunnel.\".lan\")]] = 0) do={\
    \n                      /ip dns static add address=\$tunnelIP name=(\"station-\".\$tunnel.\".lan\")\
    \n                    }\
    \n                    :if ([:len [/interface gre6 find remote-address=\$tunnelIP]]=0) do={\
    \n                      /interface gre6 add local-address=(\$v6prefix.\"::ffff\") remote-address=\$tunnelIP name=(\"gre6-tunnel\".\$tunnel)\
    \n                      #/ip address remove [find address=((172.16.1.1+(\$tunnel-1)*4).\"/30\")]\
    \n                      #/ip address add address=((172.16.1.1+(\$tunnel-1)*4).\"/30\") interface=(\"gre6-tunnel\".\$tunnel)\
    \n                      #/routing ospf network remove [find network=((172.16.1.0+(\$tunnel-1)*4).\"/30\")]\
    \n                      #/routing ospf network add area=backbone network=((172.16.1.0+(\$tunnel-1)*4).\"/30\")\
    \n                    }\
    \n                    :if ([:len [/interface eoipv6 find remote-address=\$tunnelIP]]=0) do={\
    \n                      /interface eoipv6 add local-address=(\$v6prefix.\"::ffff\") remote-address=\$tunnelIP name=(\"eoipv6-tunnel\".\$tunnel) tunnel-id=\$tunnel\
    \n                    }\
    \n                }\
    \n            }\
    \n        }\
    \n    }\
    \n  :foreach interf in=[/interface ethernet find master-port=none] do={\
    \n    :local hasOtherMaster 0\
    \n    :local hasClient 0\
    \n    :local interfName [/interface ethernet get value-name=name \$interf]\
    \n    :foreach neighbor in=[/routing ospf-v3 neighbor find where interface=\$interfName] do={\
    \n      :local neighborId [/routing ospf-v3 neighbor get value-name=router-id \$neighbor]\
    \n      :local myId [/routing ospf-v3 instance get value-name=router-id [/routing ospf-v3 neighbor get value-name=instance \$neighbor]]\
    \n      :if (\$myId>\$neighborId) do={:set \$hasOtherMaster 1}\
    \n      :if (\$myId<\$neighborId) do={:set \$hasClient 1}\
    \n    }\
    \n    :if (\$hasOtherMaster > 0) do={\
    \n      # ensure dhcp-client is activated and network is in ospf range\
    \n      #:put (\"Go client: \".\$interfName)\
    \n      :if ([:len [/ip dhcp-client find where interface=\$interfName]] < 1) do={\
    \n        /ip dhcp-client add add-default-route=no dhcp-options=hostname,clientid disabled=no interface=\$interfName use-peer-dns=no use-peer-ntp=no\
    \n      } \
    \n      /ip address set disabled=yes [/ip address find where dynamic=no disabled=no interface=\$interfName]\
    \n      /ip dhcp-server set disabled=yes [/ip dhcp-server find where disabled=no interface=\$interfName]\
    \n      /ip dhcp-client set disabled=no [/ip dhcp-client find where disabled=yes interface=\$interfName]\
    \n      :local localIpAddress [/ip address find where dynamic=yes interface=\$interfName]\
    \n      :if ([:len \$localIpAddress]=1) do={\
    \n\t      :local network [/ip address get value-name=network \$localIpAddress]\
    \n\t      :local ipAddress [/ip address get value-name=address \$localIpAddress]\
    \n\t      :local slashPos [:find \$ipAddress \"/\"]\
    \n\t      #:put \$network\
    \n\t      #:put \$ipAddress\
    \n\t      :local ospfNet (\$network.[:pick \$ipAddress \$slashPos [:len \$ipAddress]])\
    \n\t      #:put \$ospfNet\
    \n\t      :if ([:len [/routing ospf network find where network=\$ospfNet]]<1) do={\
    \n\t\t/routing ospf network add network=\$ospfNet disabled=no area=backbone\
    \n\t      }\
    \n\t} else={\
    \n\t\t/ip dhcp-client release [find where interface=\$interfName]\
    \n\t}\
    \n    } else={\
    \n      # ensure dhcp-sever is activated and network is in ospf range\
    \n      #:put (\"Go server: \".\$interfName)\
    \n      :if ([:len [/ip dhcp-client find where add-default-route=yes ]]<1) do={\
    \n        /ip address set disabled=no [/ip address find where dynamic=no disabled=yes interface=\$interfName]\
    \n        /ip dhcp-server set disabled=no [/ip dhcp-server find where disabled=yes interface=\$interfName]\
    \n        /ip dhcp-client set disabled=yes [/ip dhcp-client find where disabled=no interface=\$interfName]\
    \n        :if (\$hasClient > 0) do={\
    \n          :local network [/ip address get value-name=network   [/ip address find where dynamic=no interface=\$interfName]] \
    \n          :local ipAddress [/ip address get value-name=address  [/ip address find where dynamic=no interface=\$interfName]]  \
    \n          :local slashPos [:find \$ipAddress \"/\"]\
    \n          #:put \$network\
    \n          #:put \$ipAddress\
    \n          :local ospfNet (\$network.[:pick \$ipAddress \$slashPos [:len \$ipAddress]])\
    \n          #:put \$ospfNet\
    \n          :if ([:len [/routing ospf network find where network=\$ospfNet]]<1) do={\
    \n            /routing ospf network add network=\$ospfNet disabled=no area=backbone\
    \n          }\
    \n        }\
    \n      }\
    \n    }\
    \n  }\
    \n\
    \n}")


/system scheduler
	remove [find name=check-master]
	add interval=1m name=check-master on-event="/system script run check-master" start-time=startup

:put "configure capsman"
/caps-man channel
	remove [find]
	add band=2ghz-g/n extension-channel=disabled frequency=2412,2432,2452,2472 name=24-autoselect save-selected=yes
	add band=5ghz-onlyn extension-channel=XX frequency=5180,5220,5260,5300 name=5n-autoselect save-selected=yes
	add band=5ghz-onlyac extension-channel=XXXX frequency=5180,5260,5500,5580 name=5ac-autoselect save-selected=yes

:if ([:len [/interface wireless find]]>0) do={
	/interface wireless cap
		set enabled=yes interfaces=[/interface wireless find] certificate=none
}
:if ([:len [/caps-man configuration find]]<1) do={
	/caps-man security
		:if ([:len [find where name=("default-".$number)]]<1) do={
			add name=("default-".$number) passphrase=QK1ga6XtawnxYPQzTULgejI1gm8FTg
		}
	/caps-man configuration
		add name=base-24 channel=24-autoselect security=("default-".$number) ssid=("master-".$number) datapath.bridge=wlan-client country=switzerland datapath.client-to-client-forwarding=yes
		add name=base-5n channel=5n-autoselect security=("default-".$number) ssid=("master-".$number) datapath.bridge=wlan-client country=switzerland datapath.client-to-client-forwarding=yes
		add name=base-5ac channel=5ac-autoselect security=("default-".$number) ssid=("master-".$number) datapath.bridge=wlan-client country=switzerland datapath.client-to-client-forwarding=yes
}
:if ([:len [/caps-man provisioning find]]<1) do={
	/caps-man provisioning
		add action=create-dynamic-enabled comment="5 GHz AC" hw-supported-modes=ac master-configuration=base-5ac name-format=prefix-identity name-prefix=cap
		add action=create-dynamic-enabled comment="5 GHz N" hw-supported-modes=an master-configuration=base-5n name-format=prefix-identity name-prefix=cap
		add action=create-dynamic-enabled comment="2.4 GHz" hw-supported-modes=gn master-configuration=base-24 name-format=prefix-identity name-prefix=cap
}

:do {
      /interface ethernet poe set poe-out=auto-on [find]
} on-error={ :put "no poe device"};

/system script add dont-require-permissions=no name=import-keys owner=admin policy=ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon source="{\
    \n\t:local user \"koa\"\
    \n\t/tool fetch url=\"https://github.com/\$user.keys\" dst-path=keys\
    \n\t:local keys [/file get [/file find name=keys] contents] ;\
    \n\t:local contentLen [:len \$keys];\
    \n\
    \n\t:local lineEnd 0;\
    \n\t:local line \"\";\
    \n\t:local lastEnd 0;\
    \n\
    \n\t:while (\$lineEnd < \$contentLen) do={\
    \n\t\t:set lineEnd [:find \$keys \"\\n\" \$lastEnd];\
    \n\t\t# if there are no more line breaks, set this to be the last one\
    \n\t\t:if ([:len \$lineEnd] = 0) do={\
    \n\t\t\t:set lineEnd \$contentLen;\
    \n\t\t}\
    \n\t\t# get the current line based on the last line break and next one\
    \n\t\t:set line [:pick \$keys \$lastEnd \$lineEnd];\
    \n\t\t:set lastEnd (\$lineEnd + 1);\
    \n\t\t# don't process blank lines\
    \n\t\t:if (\$line != \"\\r\" && [:len \$line] >0) do={\
    \n\t\t\t/file print file=key.txt\
    \n\t\t\t:delay 2\
    \n\t\t\t/file set contents=\"\$line \$user\" key.txt\
    \n\t\t\t:do {\
    \n\t\t\t\t/user ssh-keys import user=admin public-key-file=key.txt\
    \n\t\t\t} on-error={ :put \"cannot import key\"};\
    \n\t\t}\
    \n\t} \
    \n}"


/interface lte apn
remove [find name=ch-swisscom]
remove [find name=ch-sunrise]
remove [find name=ch-salt]
remove [find name=fr-free]
remove [find name=fr-bouygues]
remove [find name=fr-sfr]
remove [find name=fr-orange]
add apn=gprs.swisscom.ch name=ch-swisscom
add apn=internet name=ch-sunrise
add apn=internet name=ch-salt
add apn=free name=fr-free
add apn=mmsbouygtel.com name=fr-bouygues
add apn=websfr name=fr-sfr
add apn=orange.fr authentication=pap name=fr-orange password=orange user=orange

