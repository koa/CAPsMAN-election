# CAPsMAN-election
Scripts for a Dynamic CAPsMAN network with Mikrotik RouterOS

## Idea

All RouterOS devices are preconfigured. They build a ad-hoc network and elect one device as CAPsMAN.

1. All routers connect each other by ospfv3 (IPv6)
2. Additional they build a network by ospfv2 (IPv4)
3. They provides on every ethernet interface a unique IPv4 subnet for clients
4. There is one primary CAPsMAN in the whole network
5. There is one primary DNS-Server to distribute DNS-Names to all other routers
6. The Router with a default route propagates it to the whole network


## Concept
### Base ID
* Every router has his one uniqe id (between 0 and 255).
* Every router has a loopback device
  * IPv6-Address fd58:9c23:3615::*ID*
  * IPv4-Address 172.16.0.*ID*

### Scheduled Configuration changes
There is a cron job (named check-master) everey minute who detects some topology changes and apply configuration changes (if needed).

### OSPFv3 (IPv6)
They connect by OSPFv3 over IPv6 together 
* Router ID: 172.16.0.*ID*
* search for neighbors routers on all ethernet devices

### IPv4 configuration
The IPv4-Configuration on a ethernet device depends if there is a other router with a lower router id on the same layer 2 segment.

#### If this is the single router or the router with the lowest id
* IP-Address 10.*ID*.*EthernetId*.1/24
* DHCP-Server enabled

#### If there is a router with a lower id 
* IP-Address configured by DHCP (but not set the default route)
* DHCP-Server disabled

#### OSPFv2 (IPv4)
* Router ID: 172.16.0.*ID*
* search for neighbors routers on all ethernet devices

### CAPsMAN
* The router with the lowest *ID* is the CAPsMAN.
  * It has additionally the ip fd58:9c23:3615:ffff
* There is a eoipv6 tunnel between CAPsMAN and all CAP devices
* Every local WLAN device will be connected to CAPsMAN
