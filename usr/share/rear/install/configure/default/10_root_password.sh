
# Set root password in the target system:

if test "$INSTALL_CONFIGURE_ROOT_PASSWORD" ; then
    Debug "Setting root password in the target system."
    echo -e "$INSTALL_CONFIGURE_ROOT_PASSWORD\n$INSTALL_CONFIGURE_ROOT_PASSWORD" | passwd -R $RECOVERY_FS_ROOT root
else
    Error "No root password is set in the target system without INSTALL_CONFIGURE_ROOT_PASSWORD specified."
fi

