:global number 0

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
/ip address remove [find]
/ip address add address=(172.16.0.0+$number) interface=loopback
/interface wireless cap set caps-man-addresses=fd58:9c23:3615::ffff enabled=yes interfaces=[/interface wireless find]


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
    \n        /ip address remove [find where interface~\"^gre6-tunnel\"]\
    \n        /interface gre6 remove [find where name~\"^gre6-tunnel\"]\
    \n        :if (\$isMaster!=0) do={/ipv6 address remove \$isMaster}\
    \n        :foreach addr in=[/ipv6 address find where interface=loopback] do={\
    \n            if ([/ipv6 address get \$addr address]=\"fd58:9c23:3615::ffff/128\") do={\
    \n                /ipv6 address remove \$addr\
    \n            }\
    \n        }\
    \n        :if ([:len [/interface gre6 find where name=\"gre6-tunnel-master\"]]=0) do={\
    \n            /interface gre6 add local-address=(\"fd58:9c23:3615::\".\$number) remote-address=fd58:9c23:3615::ffff name=\"gre6-tunnel-master\"\
    \n            /ip address remove [find address=((172.16.1.2+(\$number-1)*4).\"/30\")]\
    \n            /ip address add address=((172.16.1.2+(\$number-1)*4).\"/30\") interface=gre6-tunnel-master\
    \n            /routing ospf network remove [find network=((172.16.1.0+(\$number-1)*4).\"/30\")]\
    \n            /routing ospf network add area=backbone network=((172.16.1.0+(\$number-1)*4).\"/30\")\
    \n        }\
    \n        /caps-man manager set enabled=no\
    \n    } else={\
    \n        /ip address remove [find address=((172.16.1.2+(\$number-1)*4).\"/30\")]\
    \n        /routing ospf network remove [find network=((172.16.1.0+(\$number-1)*4).\"/30\")]\
    \n        /interface gre6 remove [find where name=\"gre6-tunnel-master\"]\
    \n        :if (\$isMaster=0) do={\
    \n            /ipv6 address add address=fd58:9c23:3615::ffff/128 interface=loopback\
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








