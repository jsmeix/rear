
# YaST network card setup in the target system:

if test "$INSTALL_CONFIGURE_SUSE_YAST_NETWORK_SETUP" ; then
    # YaST network card setup in the target system (without having ncurses stuff in the output via TERM=dumb)
    # plus automated respose to all requested user input via yes '' (i.e. only plain [Enter] as user input):
    Debug "Let YaST setup the network card in the target system via 'yast2 --ncurses lan $INSTALL_CONFIGURE_SUSE_YAST_NETWORK_SETUP'."
    chroot $RECOVERY_FS_ROOT /bin/bash -c "yes '' | TERM=dumb yast2 --ncurses lan $INSTALL_CONFIGURE_SUSE_YAST_NETWORK_SETUP"
fi

