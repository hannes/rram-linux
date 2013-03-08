#!/bin/bash
# the location of the ramdisk to export
ramdisk=/mnt/ramdisk


if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

[[ "$1" =~ ^[0-9]+$ ]] || { echo "Give me the number of GBs to donate as first parameter." >&2; exit 1; }
[[ "$2" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] ||  { echo "Give me the IPoIB IP of the node that wants our memory as second parameter" >&2; exit 1; }

size=$1
ip=$2

echo "### create a ramdisk of $size GB and export to $ip using NFS/RDMA"
echo

echo "stopping nfs/rpcbind server"
service nfs-server stop
service rpcbind stop

if mount | grep --quiet $ramdisk; then
  echo "unmounting ramdisk at $ramdisk first"
  umount $ramdisk
fi

if grep --quiet $ramdisk /etc/exports; then
  echo "/etc/exports contains $ramdisk NFS export, not adding"
else
  echo "adding NFS export for $ramdisk to /etc/exports"
  echo "$ramdisk *(rw,fsid=5,async,insecure,no_root_squash)" >> /etc/exports
fi

if grep --quiet $ip /etc/hosts.allow; then
  echo "/etc/hosts.allow contains $ip, not adding"
else
  echo "adding $ip to /etc/hosts.allow"
  echo "ALL: $ip" >> /etc/hosts.allow
fi

mkdir -p $ramdisk
echo "creating ramdisk at $ramdisk with size $size GB"
mount -t ramfs -o size=$size"g" tmpfs $ramdisk

if ! mount | grep --quiet $ramdisk; then
echo "Somehow unable to create $size GB ramdisk at $ramdisk :(" >&2
exit 1
fi

echo "writing loopback file to ramdisk (faster here...)"
let megs=$size*1024
dd if=/dev/zero of=/mnt/ramdisk/lo bs=1M count=$megs

if ! ls $ramdisk/lo > /dev/null 2> /dev/null; then
echo "Somehow unable to create loopback file :(" >&2
exit 1
fi

echo "loading nfs-rdma server kernel module (svcrdma)"
modprobe svcrdma 

if ! lsmod | grep --quiet svcrdma; then 
echo "Somehow unable to load svcrdma module :(" >&2 
exit 1 
fi

echo "starting rpcbind/nfs again"
service rpcbind start
service nfs-server start
echo "rdma 2050" > /proc/fs/nfsd/portlist

echo "done"

