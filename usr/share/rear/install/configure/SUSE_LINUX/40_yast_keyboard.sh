
# YaST keyboard layout setting in the target system:

if test "$INSTALL_CONFIGURE_SUSE_YAST_KEYBOARD_LAYOUT" ; then
    Debug "Let YaST set the keyboard layout in the target system to '$INSTALL_CONFIGURE_SUSE_YAST_KEYBOARD_LAYOUT'."
    # Set keyboard in the target system (without having ncurses stuff in the output via TERM=dumb):
    chroot $RECOVERY_FS_ROOT /bin/bash -c "TERM=dumb yast2 --ncurses keyboard set layout=$INSTALL_CONFIGURE_SUSE_YAST_KEYBOARD_LAYOUT"
fi

