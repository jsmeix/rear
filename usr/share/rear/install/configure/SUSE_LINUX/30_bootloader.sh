
# Configure and install bootloader in the target system:

if test -b "$INSTALL_CONFIGURE_SUSE_BOOTLOADER_DEVICE" ; then
    Debug "Making initrd verbosely in the target system."
    chroot $RECOVERY_FS_ROOT /sbin/mkinitrd -v
    Debug "Making bootloader configuration in the target system (setting GRUB_DISTRIBUTOR to '$INSTALL_CONFIGURE_SUSE_GRUB_DISTRIBUTOR')."
    if test "$INSTALL_CONFIGURE_SUSE_GRUB_DISTRIBUTOR" ; then
        sed -i -e "s/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR=\"$INSTALL_CONFIGURE_SUSE_GRUB_DISTRIBUTOR\"/" $RECOVERY_FS_ROOT/etc/default/grub
    fi
    chroot $RECOVERY_FS_ROOT /usr/sbin/grub2-mkconfig -o /boot/grub2/grub.cfg
    Debug "Installing bootloader in the target system into '$INSTALL_CONFIGURE_SUSE_BOOTLOADER_DEVICE'."
    chroot $RECOVERY_FS_ROOT /usr/sbin/grub2-install --force $INSTALL_CONFIGURE_SUSE_BOOTLOADER_DEVICE
else
    Error "No bootloader gets installed in the target system without INSTALL_CONFIGURE_SUSE_BOOTLOADER_DEVICE specified properly (must be a block device)."
fi

