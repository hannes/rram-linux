#!/bin/bash
# the location where the aggregated volume is to be mounted
stripedisk=/mnt/ramstripe
stripedevice=/dev/md/md-ramstripe
remoteramdisk=/mnt/ramdisk
mountprefix=/mnt/nfs-
remotelofile=lo


echo "## Combine Ramdisks exported by remote nodes..."
echo

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

mkdir -p $stripedisk

if mount | grep --quiet $stripedisk; then
  echo "Unmounting array at $stripedisk first"
  umount $stripedisk
fi

if  ls $stripedevice > /dev/null 2> /dev/null; then
	echo "There is already a RAID array at $stripedevice, disassembling." >&2
	mdadm --stop $stripedevice
fi

# releasing loop devices, TODO: only do this for NFS-mounted loop devices.
losetup -d /dev/loop*
# releasing NFS mounts
umount -f $mountprefix*

echo "## loading nfs-rdma client kernel module (xprtrdma)"
modprobe xprtrdma 

if ! lsmod | grep --quiet xprtrdma; then 
echo "Somehow unable to load xprtrdma module :(" >&2 
exit 1 
fi

lo=0
loopdevices=""
for ip in "$@"
do
	[[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] ||  { echo "Give me the IPoIB IPs of the node that give us memory as parameters" >&2; exit 1; }
	echo "## setting up $ip"
	mountdir="/mnt/nfs-$ip"
	loopdevice="/dev/loop$lo"

	if ! ls $loopdevice > /dev/null 2> /dev/null; then
		echo "Not enough loopback devices! Google for the kernel boot option..." >&2
		exit 1
	fi

	mkdir -p $mountdir
	echo "mounting $remoteramdisk from $ip to $mountdir"
	mount -o rdma,port=2050,nolock,vers=3 $ip:$remoteramdisk $mountdir

	if ! mount | grep --quiet $mountdir; then
		echo "Somehow unable to mount NFS from $ip to $mountdir :(" >&2
		exit 1
	fi

	echo "setting up loop device $loopdevice to $mountdir/$remotelofile"
	losetup $loopdevice $mountdir/$remotelofile

	if ! losetup -a | grep --quiet $remotelofile; then
	echo "Somehow unable to create loopback device from $remotelofile to $loopdevice :(" >&2
	exit 1
	fi

	loopdevices+=" $loopdevice"
	let lo=$lo+1
	echo
done


echo "## putting loopback devices together"
mkdir -p $stripedisk
echo $loopdevices
let devicescount=$lo

# Volume manager assembles loopback devices into virtual RAID0 array
mdadm --create /dev/md/md-ramstripe --run --chunk=2048 --level=0 --raid-devices=$devicescount $loopdevices
# Create file system on array
mkfs.ext4 /dev/md/md-ramstripe
# Mount with performance-friendly options
mount -o data=writeback,noatime,nodiratime,barrier=0,noacl,nobh,noquota /dev/md/md-ramstripe $stripedisk


if ! mount | grep --quiet $stripedisk; then
echo "Somehow unable to create array at $stripedisk :(" >&2
exit 1
fi

echo "## looks like everything went well. Some details about your new remote memory array:"
mdadm --misc --detail /dev/md/md-ramstripe
mount | grep $stripedisk
df -h $stripedisk
