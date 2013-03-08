rram-linux
==========

The scripts in this repository allow you to mount remote memory from a number of 'provider' nodes into a large virtual volume on the 'demander' node. To achieve best performance, NFS over [RDMA](http://en.wikipedia.org/wiki/Remote_direct_memory_access) is used. Hence, please make sure your RDMA setup is functioning before trying this. Furthermore, we have developed these scripts on Fedora 16 installations (Kernel 3.3.4-3), behaviour on other distributions is 'unspecified', but adaption should be possible. Please beware that these scripts are provided without any guarantees, and require root privileges. Test them responsibly...


### Usage
There are two classes of nodes in our setup, memory providers and memory requesters. Typically, a number of providers provide memory to a single requester. 

#### Memory Providers
On all memory providers, run

`./provider.sh [SharedGBs] [RequesterIP]`

* `SharedGBs` is the amount of memory in Gigabytes to be shared. We recommend leaving 10-20% of memory to the provider's OS.
* RequesterIP is the IP address of the RDMA-enabled network interface of the requester node. This is used to add that IP to `/etc/hosts.allow`.

For example, on our systems we ran `./provider.sh 14 192.168.64.35`

This command performed the following actions:
* Stop the NFS server if running
* Add `192.168.64.35` to `/etc/hosts.allow` if not already present
* Create a Ramdisk with a size of 14 GB at `/mnt/ramdisk` with the specified size (Mountpoint is created if not present)
* Add a NFS export directive to `/etc/exports` for the Ramdisk at `/mnt/ramdisk`
* Write a file the size of the ramdisk (14GB) to `/mnt/ramdisk/lo` (will be used later)
* Load the `svcrdma` kernel module, which allows NFS exports over RDMA
* Start the NFS server and enable RDMA transport on port 2050

#### Memory Requester
On the memory demander, run

`./requester.sh [ProviderIP1] [ProviderIP2] [ProviderIP2] ...`
* ProviderIP* are the IP addresses of the RDMA-enabled network interfaces on the provider nodes.

For example, on our system we ran `./requester.sh 192.168.64.20 192.168.64.21 192.168.64.22`  (and so on, 13 providers in total)

This command performed the following actions:
* Load the `xprtrdma` kernel module, which allows NFS mounts over RDMA
* For each IP given:
  * Mount the NFS export `/mnt/ramdisk` from the remote node to the mount point `/mnt/nfs-[IP]`, e.g. `/mnt/nfs-192.168.64.20` (created if not present)
  * Set up a loop device to the file `lo` on the NFS mount, e.g. `/dev/loop0` -> `/mnt/nfs-192.168.64.20/lo`
* Create a software RAID volume for all the loop devices just set up at `/dev/md/md-ramstripe`
* Format the RAID volume at `/dev/md/md-ramstripe` with the `ext4` file system
* Mount the RAID volume at `/dev/md/md-ramstripe` to `/mnt/ramstripe`

If all went well, you will see a corresponding message and some debug output. Check that everything worked by typing `df -h`, your new volume should show up with a size that corresponds to the memory provided by all nodes.

To disconnect, run the following commands on the provider node:
* Unmount the `mdadm` software RAID volume: `umount /mnt/ramstripe`
* Remove the RAID volume: `mdadm --stop /dev/md/md-ramstripe`
* Disconnect all loopback devices: `losetup -d /dev/loop*`
* Unmount all NFS mounts: `umount -f /mnt/nfs-**`

These commands are also automatically issued at the begin of `./requester.sh`, so beware if you are also using loop devices etc.

### Known Issues
* Make sure you remove the array, disconnect the loopback devices, and unmount the NFS shares  on the requester before stopping the NFS server on the provider or even remove the ramdisk. On Fedora 16, this caused some kernel panics.


