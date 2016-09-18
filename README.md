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

# Setup
## Requirements
* Some Routers with RouterOS from Mikrotik
* Connections between the routers (Ethernet cable)

## Software Update (if needed) 
1. Update router at least to 6.36.3

  `/system package update install`

2. Install wireless-rep (if not already there)
  1. Download extra packages from http://www.mikrotik.com/download for your Platform
  2. Extract wireless-rep-* and copy to your device
  3. Reboot it
3. Enable wireless-rep and IPv6

```
/system package
  enable ipv6
  enable wireless-rep
/system reboot
```

## Setup Configuration
1. Log into device and remove all current configuration

  `/system reset-configuration no-defaults=yes`

2. Now connect device by serial console, mac-telnet (https://github.com/haakonnessjoen/MAC-Telnet) or Winbox (http://wiki.mikrotik.com/wiki/Manual:Winbox)
3. Set *ID* to variable $number. Where *ID* is a unique number for this Device.

  `:global number `*ID*

4. Open config.rsc with your favorite text editor
5. Copy and paste the whole content it into the console on router.
6. Set password
   `/password`
7. Set a idendity
   `/system identity set name=router-`*ID*

Now you are ready and can connect a client PC to any ethernet-connection on your device.
If your device has the *ID* 20 you can connect the web ui by http://172.16.0.20/
