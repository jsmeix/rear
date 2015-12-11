
# Create etc/fstab in the target system:

harddisk_device="/dev/sda"
swap_partition_number="1"
swap_partition=$harddisk_device$swap_partition_number
system_partition_number="2"
system_partition=$harddisk_device$system_partition_number
system_partition_filesystem="ext4"

mkdir $RECOVERY_FS_ROOT/etc
pushd /dev/disk/by-uuid/
swap_partition_uuid=$( for uuid in * ; do readlink -e $uuid | grep -q $swap_partition && echo $uuid || true ; done  )
system_partition_uuid=$( for uuid in * ; do readlink -e $uuid | grep -q $system_partition && echo $uuid || true ; done  )
popd
( echo "UUID=$swap_partition_uuid swap swap defaults 0 0"
  echo "UUID=$system_partition_uuid / $system_partition_filesystem defaults 0 0"
) > $RECOVERY_FS_ROOT/etc/fstab

