
# Enabling systemd unit files in the target system:

if test "$INSTALL_CONFIGURE_SYSTEMD_UNIT_FILES" ; then
    local systemd_unit_file
    for systemd_unit_file in $INSTALL_CONFIGURE_SYSTEMD_UNIT_FILES ; do
        Debug "Enabling systemd unit file '$systemd_unit_file' in the target system."
        chroot $RECOVERY_FS_ROOT systemctl enable $systemd_unit_file
    done
fi

