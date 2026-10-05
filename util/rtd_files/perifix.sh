#!/bin/bash


# this needs to be placed in the /etc/init.d folder and a symbolic link needs to be created in the /etc/rc3.d that points to this location 

# find all pericom boards that we use and set the ACS bits to 0b0100
lspci | awk '/PI7C9X2G404/ { print $1 }' > bus_members.txt
for fn in `cat bus_members.txt`; do setpci -s "$fn" 226.w=0:4; done
rm bus_members.txt
