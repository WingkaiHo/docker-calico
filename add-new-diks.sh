set -e
set -x

if [ -f /etc/disk_added_date ]
then
   echo "disk already added so exiting."
   exit 0
fi


sudo fdisk -u /dev/vdb <<EOF
n
p
1


t
8e
w
EOF

pvcreate /dev/vdb1
vgextend vagrant-vg /dev/vdb1
lvextend -l +100%FREE /dev/vagrant-vg/root

# for ext4
resize2fs /dev/vagrant-vg/root
# for xfs
xfs_growfs /dev/centos/root 
