
# Make /proc /sys /dev from the installation system available in the target system:
for mountpoint_directory in proc sys dev ; do
    mkdir $RECOVERY_FS_ROOT/$mountpoint_directory
done
mount -t proc none $RECOVERY_FS_ROOT/proc
mount -t sysfs sys $RECOVERY_FS_ROOT/sys
mount -o bind /dev $RECOVERY_FS_ROOT/dev

